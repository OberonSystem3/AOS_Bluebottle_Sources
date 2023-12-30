MODULE MediaPlayer; (** AUTHOR "PL/staubesv"; PURPOSE "Media Player"; *)
(**
 *
 * History:
 *
 *	15.02.2006	Set UpdateInterval to 500ms, optionally open player window in current view, 
 *				added SetEofAction & EofHandler for testing purposes, improved closing behaviour (staubesv) 
 *
 * TODOs:
 *	- 	reuse filler threads
 *	-	optimize filler threads seek procedure (first look at already decoded pictures before flushing them - maybe we can use them)
 *	-	Does the player need to be able to play standalone at all? (Remove GUI related code from module?)
 *	-	implement/finish drop frame mechanism
 *	- 	improve SetPos 
 *	-	Don't change volume of audio play channels
 *	- 	USE same position info for both audio and video!!! (milliseconds)
 *)
 
IMPORT
	AosSound, AosCodecs, AosOut, AosIO, AosFS, AosCommands, AosKernel, AosModules, WMTransitions,
	WMRectangles, WMGraphics, WMWindowManager, Raster, Utilities;

CONST
	(* Result codes *)
	Ok* = 0;
	CouldNotOpenStream* = 1;	(* Could not open the specified ressource as stream *)
	AudioNotCompatible* = 2;	(* Audio decoder found but not compatible *)
	VideoNotCompatible* = 3;	(* Video decoder found but not compatible *)
	DemuxNotCompatible* = 4; 	(* Demultiplexer found but not compatible *)
	NoVideoDecoder* = 5;		
	NoAudioDecoder* = 6;
	NoDecoders* = 7;
	WrongParameters* = 8;
	
	(**	Player States 											*)
	NotReady* = 1;		(* No files opened, not playing anything 	*)
	Ready* = 2;	 		(* Player is ready to play 				*)
	Playing* = 3;	 	(* Player is playing a video 				*)
	Paused* = 4;		(* Player is paused 						*)
	Stopped* = 5;		(* Player is stopped 					 	*)
	InTransition* = 7;	(* Transition between two videos 		*)
	Finished* = 9;		(* Finished video/audio					*)
	Closed* = 10;		(* Player has been closed 				*)
	Error* = 99;			(* Player is in error state 				*)

	(* Next state field *)
	NoRequest = 0;
	
	(* Audio buffers *)
	AudioBufferSize = 288; 
	AudioBuffers = 160;
	AudioConstantDelay = 100; (* Guessed time from playchannel.Start until audio is played *)
	
	(* How many video frames may filler thread decode ahead? *)
	VBUFFERS = 10;
	
	(* Interval in millisecond when update is called (it is, however, always called when the state of the player changes *)
	UpdateInterval = 500;
			
	(* Should the player window be forced to be always fullscreen? *)
	ForceFullscreen = FALSE;
	
	(* Should the player window be forced to open in the default view? (Makes sense when operating over VNC) *)
	ForceDefaultView = FALSE;
	
	(* Time in milliseconds when pointer should disappear. 0 = Cursor always hidden *)
	PointerInvisibleAfter = 2000; 
	
	(* Gather performance data. Will be displayed on kernel log each time a filler is closed (loaded other video / quit) *)
	PerformanceStats = FALSE;
			
	TraceAll = {0..31};
	TraceNone = {};
	TracePlayer = {1};		
	TraceOpen = {2};		(* Get new context 			*)
	TraceFiller = {3};			(* Video filler thread 		*)
	TraceTransitions = {4};	(* Video transitions 			*)
	TraceStates = {5}; 		(* Player states 				*)
	TraceRendering = {6}; 	(* Per frame rendering stats 	*)
	TraceEof = {7};			(* Trace calls to end of file handlers *)		
	
	Trace = TraceNone;
	
	Debug = TRUE;
	
TYPE
	(* video buffer *)
	VideoBuffer = WMGraphics.Image;

	(* buffer pool for the video frames *)
	VideoBufferPool = OBJECT
	VAR 
		head, num: LONGINT; 
		buffer: POINTER TO ARRAY OF VideoBuffer;

		PROCEDURE &Init*(n: LONGINT);
		BEGIN
			head := 0; num := 0; NEW(buffer, n)
		END Init;
				
		PROCEDURE Add*(x: VideoBuffer);
		BEGIN {EXCLUSIVE}
			AWAIT(num # LEN(buffer));
			buffer[(head+num) MOD LEN(buffer)] := x;
			INC(num)
		END Add;

		PROCEDURE Remove*(): VideoBuffer;
		VAR x: VideoBuffer;
		BEGIN {EXCLUSIVE}
			AWAIT(num # 0);
			x := buffer[head];
			head := (head+1) MOD LEN(buffer);
			DEC(num);
			RETURN x
		END Remove;
		
		PROCEDURE NofBuffers*(): LONGINT;	
		BEGIN {EXCLUSIVE}
			RETURN num
		END NofBuffers;	
		
	END VideoBufferPool;
	
TYPE

	KeyEventHandler* = PROCEDURE {DELEGATE} (ucs : LONGINT; flags : SET; keysym : LONGINT);
	
	PointerDownHandler* = PROCEDURE {DELEGATE} (x, y : LONGINT; keys : SET); 

	(** default Player Window where the video is played *)		
	PlayerWindow* =  OBJECT(WMWindowManager.DoubleBufferWindow)
	VAR 
		player : Player;
		rect : WMRectangles.Rectangle;
		videoWidth, videoHeight : LONGINT;
		
		(* Fullscreen functionality related *)
		fullscreen- : BOOLEAN;
		lastFrame : WMGraphics.Image; 
		posX, posY : LONGINT; (* Last window position in windowed-mode *)
		
		(* Pointer invisible functionality related *)
		pointerVisible : BOOLEAN;
		timer : AosKernel.Timer;
		lastTimestamp, timestamp : LONGINT; (* Timemark when mouse pointer was moved last time *)
		
		(* External handlers for key/pointer events. CURRENTLY ACCESS IS NOT SYNCHRONIZED! *)
		extPointerDownHandler* : PointerDownHandler;
		extKeyEventHandler* : KeyEventHandler;
		
		(* Active object control *)
		alive, dead : BOOLEAN;
		
		PROCEDURE &New(w, h : LONGINT; alpha : BOOLEAN; player : Player; autoHideCursor : BOOLEAN);
		BEGIN
			SELF.player := player; videoWidth := w; videoHeight := h; posX := 100; posY := 100;
			rect := WMRectangles.MakeRect(0, 0, w, h);
			Init(w, h, alpha);
			manager := WMWindowManager.GetDefaultManager ();
			IF ForceDefaultView THEN 
				manager.Add(posX, posY, SELF, {WMWindowManager.FlagFrame});
			ELSE
				WMWindowManager.ExtAddWindow (SELF, posX, posY, {WMWindowManager.FlagFrame});
			END;
			manager.SetFocus(SELF);			
			SetTitle(WMWindowManager.NewString("Video Panel"));
			IF autoHideCursor & (PointerInvisibleAfter > 0) THEN
				NEW(timer);
				alive := TRUE; dead := FALSE;
				SetPointerVisible(TRUE);
			ELSE
				alive := FALSE; dead := TRUE; 
				SetPointerVisible(FALSE);
			END; 
			fullscreen := FALSE;
		END New;
		
		(** Toggle between fullscreen and window mode *)
		PROCEDURE ToggleFullscreen*;
		VAR view : WMWindowManager.ViewPort; width, height : LONGINT;
		BEGIN
			IF fullscreen THEN
				ReInit(videoWidth, videoHeight);
				manager.SetWindowSize(SELF, videoWidth, videoHeight);
				rect := WMRectangles.MakeRect(0, 0, videoWidth, videoHeight);
				manager.SetWindowPos(SELF, posX, posY);
				IF lastFrame # NIL THEN ShowFrame(lastFrame); END; 
				fullscreen := FALSE;
			ELSE
				posX := bounds.l; posY := bounds.t;
				view := WMWindowManager.GetDefaultView();
				width := ENTIER(view.range.r - view.range.l);
				height := ENTIER(view.range.b - view.range.t);	
				ReInit(width, height);
				manager.SetWindowSize(SELF, width, height);
				manager.SetWindowPos(SELF, ENTIER(view.range.l), ENTIER(view.range.t));				
				rect := WMRectangles.MakeRect(0, 0, width, height);
				IF lastFrame # NIL THEN ShowFrame(lastFrame); END; 
				fullscreen := TRUE;
			END;
		END ToggleFullscreen;
						
		(* Overwrite draw procedure because we do not want any interpolation *)
		PROCEDURE Draw*(canvas : WMGraphics.Canvas; w, h, q : LONGINT);
		BEGIN
			Draw^(canvas, w, h, 0); 
		END Draw;  
		
		PROCEDURE Close;
		BEGIN
			player.Close;
			alive := FALSE; IF timer # NIL THEN timer.Wakeup; END;
			BEGIN {EXCLUSIVE} AWAIT(dead); END;
			Close^;
		END Close;	

		(* Key Handler *)
		PROCEDURE KeyEvent(ucs : LONGINT; flags : SET; keysym : LONGINT);
		BEGIN
			IF extKeyEventHandler # NIL THEN extKeyEventHandler(ucs, flags, keysym); END;
			IF keysym = 0FF50H THEN (* Cursor Home *)
				player.ToggleFullScreen(NIL, NIL)
			END;
		END KeyEvent;		
		
		PROCEDURE ShowBlack*;
		VAR rect : WMRectangles.Rectangle;
		BEGIN
			Raster.Clear(img);
			Invalidate(rect);
		END ShowBlack;		
	
		PROCEDURE ShowFrame*(frame : WMGraphics.Image);
		VAR s, d : WMRectangles.Rectangle; h, w : LONGINT; 
		BEGIN
			BEGIN {EXCLUSIVE} (* Don't execute the same time as SELF.ReInit does *)
				lastFrame := frame;
				IF (img.width = frame.width) & (img.height = frame.height) THEN
					canvas.DrawImage(0, 0, frame, WMGraphics.ModeCopy);
					d := WMRectangles.MakeRect(0, 0, img.width, img.height)
				ELSE
					s := WMRectangles.MakeRect(0, 0, frame.width, frame.height);
					IF (img.width/frame.width) < (img.height/frame.height) THEN
						h := ENTIER(frame.height/frame.width*img.width); 
						d := WMRectangles.MakeRect(0, (img.height- h) DIV 2, img.width, img.height - (img.height - h) DIV 2)
					ELSE	
						w := ENTIER(frame.width/frame.height*img.height);
						d := WMRectangles.MakeRect((img.width - w) DIV 2, 0, img.width - (img.width - w) DIV 2, img.height)
					END;
					canvas.ScaleImage(frame, s, d, WMGraphics.ModeCopy, 0)
				END;
			END;	
			Swap;
			Invalidate(d);
		END ShowFrame; 
				
		(* Make pointer visible when it is moved *)
		PROCEDURE PointerMove(x, y : LONGINT; keys : SET);
		BEGIN
			IF PointerInvisibleAfter > 0 THEN 
				lastTimestamp := AosKernel.GetTimer();
				SetPointerVisible(TRUE); 
			END;
		END PointerMove;
	
		PROCEDURE PointerDown(x, y : LONGINT; keys : SET);
		BEGIN
			IF PointerInvisibleAfter > 0 THEN 
				lastTimestamp := AosKernel.GetTimer();
				SetPointerVisible(TRUE);			
				IF keys # {2} THEN ToggleFullscreen; END;
				IF extPointerDownHandler # NIL THEN extPointerDownHandler(x, y, keys); END;
			END;
		END PointerDown;
		
		PROCEDURE SetPointerVisible(visible : BOOLEAN);
		BEGIN (* Since pointer move messages are not just sent once, we don't need to synchronize access to the pointerVisible field *)
			IF visible THEN 
				SetPointerInfo(manager.pointerStandard);
			ELSE
				SetPointerInfo(manager.pointerNull);
			END;
		END SetPointerVisible;
		
	BEGIN {ACTIVE}
		IF PointerInvisibleAfter < 1 THEN alive := FALSE; END; 
		WHILE alive DO (* Make pointer invisible when it is not moved for a certain amount of time *)
			timer.Sleep(PointerInvisibleAfter + 10);
			timestamp := AosKernel.GetTimer();
			IF (timestamp - lastTimestamp >= PointerInvisibleAfter) THEN
				 SetPointerVisible(FALSE); 
			END; 
		END; 
		BEGIN {EXCLUSIVE} dead := TRUE; END;
	END PlayerWindow;
	
TYPE
	
	(* buffer filler thread *)
	Filler = OBJECT
	VAR 
		videoDecoder : AosCodecs.VideoDecoder;
		vBufferPool : VideoBufferPool;
		readyBufferPool : VideoBufferPool;
		vBuffer : VideoBuffer;
		blackBuffer : VideoBuffer;
		drop : LONGINT;
		frame : VideoBuffer;
		
		alive, positionChanged : BOOLEAN;
		next : Filler;
		
		(* Performance statistics *)
		framesDecoded : LONGINT;
		min, max, tot : LONGINT; 
		perf : LONGINT;
		dropped : LONGINT;
		
		PROCEDURE &New(videoWidth, videoHeight : LONGINT; videoDecoder : AosCodecs.VideoDecoder);
		VAR i : LONGINT;
		BEGIN
			(* empty buffers *)
			NEW(vBufferPool, VBUFFERS);
			FOR i := 0 TO VBUFFERS-1 DO
				NEW(vBuffer);
				Raster.Create(vBuffer, videoWidth, videoHeight, Raster.BGR565);
				vBufferPool.Add(vBuffer)
			END;
			(* full buffers *)
			NEW(readyBufferPool, VBUFFERS);
			(* temp buffer *)
			NEW(blackBuffer); NEW(frame);
			Raster.Create(blackBuffer, videoWidth, videoHeight, Raster.BGR565);
			Raster.Create(frame, videoWidth, videoHeight, Raster.BGR565);
			SELF.videoDecoder := videoDecoder;
			alive := TRUE; positionChanged := FALSE;
			IF PerformanceStats THEN
				min := MAX(LONGINT); 
			END;
		END New;		
		
		(* Returns the next Buffer ready to be played *)
		PROCEDURE GetNextBuffer(): VideoBuffer;
		BEGIN
			IF readyBufferPool.NofBuffers() > 0 THEN
				RETURN readyBufferPool.Remove()
			ELSE
				INC(dropped);
				RETURN blackBuffer;
			END;
		END GetNextBuffer;
		
		(* Puts the buffer back into the empty BufferPool *)
		PROCEDURE ReturnBuffer(buf : VideoBuffer);
		BEGIN
			IF buf # blackBuffer THEN
				vBufferPool.Add(buf)			
			END
		END ReturnBuffer;
			
		PROCEDURE DropFrames(n : LONGINT);
		BEGIN
			drop := n
		END DropFrames;
		
		PROCEDURE GetPos(): LONGINT;
		BEGIN {EXCLUSIVE}
			 RETURN videoDecoder.GetCurrentFrame()
		END GetPos;
		
		PROCEDURE SeekAndGetFrame(pos: LONGINT; VAR f : WMGraphics.Image; VAR res : LONGINT);
		BEGIN  {EXCLUSIVE}
			ASSERT(frame # NIL);
			WHILE readyBufferPool.NofBuffers() > 0 DO (* flush Buffer *)
				vBufferPool.Add(readyBufferPool.Remove())
			END;
			videoDecoder.SeekFrame(pos, TRUE, res);
			videoDecoder.Next; videoDecoder.Next;
			videoDecoder.Render(frame);
			f := frame;
			videoDecoder.SeekFrame(pos, TRUE, res); 
			videoDecoder.Next;
			IF videoDecoder.HasMoreData() THEN positionChanged := TRUE; END;
		END SeekAndGetFrame;
		
		PROCEDURE SeekFrame(pos : LONGINT; isKeyFrame : BOOLEAN; VAR res : LONGINT);
		BEGIN {EXCLUSIVE}
			WHILE readyBufferPool.NofBuffers() > 0 DO (* flush Buffer *)
				vBufferPool.Add(readyBufferPool.Remove())
			END;
			videoDecoder.SeekFrame(pos, TRUE, res);
			videoDecoder.Next;
			IF videoDecoder.HasMoreData() THEN positionChanged := TRUE; END;
		END SeekFrame;
			
		(* Returns the number of decoded frames available *)	
		PROCEDURE NofFullBuffers() : LONGINT;
		BEGIN
			RETURN readyBufferPool.NofBuffers()
		END NofFullBuffers;
		
		(* Terminate the filler process, but still grant access to already decoded frames *)
		PROCEDURE Stop;
		BEGIN {EXCLUSIVE}
			IF Trace * TraceFiller # {} THEN AosOut.String("MediaPlayer: Filler stopped."); AosOut.Ln; END;	
			alive := FALSE;
		END Stop;
		
		(* Terminate the filler process *)
		PROCEDURE Close;
		BEGIN {EXCLUSIVE}
			IF Trace * TraceFiller # {} THEN AosOut.String("MediaPlayer: Closing filler..."); AosOut.Ln; END;
			alive := FALSE;
			(* To establish await conditions required to exit the active objects body *)
			IF readyBufferPool.NofBuffers() > 0 THEN vBufferPool.Add(readyBufferPool.Remove()); END;
		END Close;
		
	BEGIN {ACTIVE}		
		WHILE alive DO
			IF videoDecoder.HasMoreData() THEN
				vBuffer := vBufferPool.Remove(); (* Will block of no buffers available *)
				BEGIN {EXCLUSIVE}
					IF alive & videoDecoder.HasMoreData() THEN 
						IF PerformanceStats THEN
							perf := AosKernel.GetTimer();
						END;
						videoDecoder.Next;
						videoDecoder.Render(vBuffer);
						IF PerformanceStats THEN
							perf := AosKernel.GetTimer() - perf;
							IF perf < min THEN min := perf;
							ELSIF perf > max THEN max := perf;
							END;
							INC(tot, perf);
							INC(framesDecoded);
						END;
					END;
				END;	
				readyBufferPool.Add(vBuffer);
			ELSE
				BEGIN {EXCLUSIVE} AWAIT(positionChanged OR ~alive); positionChanged := FALSE; END;
			END;
		END;
		IF Trace * TraceFiller # {} THEN AosOut.String("MediaPlayer: Filler closed."); AosOut.Ln; END;
		IF PerformanceStats THEN
			IF framesDecoded > 0 THEN 
				AosOut.String("MediaPlayer: Decoded "); AosOut.Int(framesDecoded, 0); AosOut.String(" frames in "); AosOut.Int(tot, 0);
				AosOut.String("ms (min: "); AosOut.Int(min, 0); 
				AosOut.String(", avg: "); AosOut.Int(tot DIV framesDecoded, 0); AosOut.String(", max: "); AosOut.Int(max, 0); AosOut.String(")");
				AosOut.String(", "); AosOut.Int(dropped, 0); AosOut.String(" frames not decoded in time"); AosOut.Ln;
			END;			
		END;
	END Filler;
	
TYPE

	Setup* = POINTER TO RECORD
		uri- : ARRAY 256 OF CHAR; 
		
		hasAudio-, hasVideo- : BOOLEAN;	(* Does the opened ressource contain audio and video? *)
		canSeek- : BOOLEAN;				(* Is seeking supported? *)
		
		maxTime- : LONGINT;				(* Duration of Video/Audio in 1/10 sec *)

		(* If hasVideo *)
		width-, height- : LONGINT;			(* width and height of video frames if applicable *)
		mspf- : LONGINT;					(* milliseconds per frame *)
		maxFrames- : LONGINT;				
		
		(* If hasAudio *)
		channels-, bits-, rate-: LONGINT; 	(* Number of audio channels, resolution and rate *)
	END;
	
	(* The context record stores all information needed to play the associated ressource *)
	Context = POINTER TO RECORD
		uri : ARRAY 256 OF CHAR;					(* Ressource to be played *)
		hasVideo, hasAudio : BOOLEAN;	 			(* Does the ressource contain video and/or audio? *)
		canSeek : BOOLEAN;						(* Do the video and the audio stream support seeking? *)

		pos, oldPos : LONGINT;						(* Current/last position in stream *)

		(* Only accessible if hasVideo = TRUE *)
		video : AosCodecs.VideoDecoder;		
		maxFrames, maxTime : LONGINT;	
		width, height, mspf : LONGINT;				(* width, heigth & milliseconds per frame of video *)
		filler : Filler;									(* Video Filler Thread *)
		vBuffer : VideoBuffer;						(* Video Buffer Object *)

		(* Only accessible if hasAudio = TRUE *)
		audio : AosCodecs.AudioDecoder;
		channels, bits, rate : LONGINT;				(* Number of audio channels, their resolution (bits) and sampling rate (rate) (reported by GetAudioInfo() *)
		posRate : LONGINT;							(* StreamInfo reports other rate than GetAudioInfo(). Use this value for calculating audio positions  *)
		aBuffer : AosSound.Buffer;
		channel : AosSound.Channel;
		bufferpool : AosSound.BufferPool;
		delay : LONGINT;							(* Delay in milliseconds induced by using audio buffers *)
		
		(* Transition related *)
		transition : WMTransitions.TransitionFade;	(* Transition Object*)
		transitionFrame : LONGINT;					(* Current frame in Transition *)
		transitionDuration : LONGINT;				(* Number of frames the transition endures *)
		transitionImg : VideoBuffer;					(* Transition target video buffer *)
		black : VideoBuffer; 							(* Black frame *)
	END;

TYPE

	EofProc = PROCEDURE {DELEGATE} (sender, data: ANY);		

	(* Decouples end-of-file handlers from media player main loop. This enables eof handlers to call methods
	 * of the media player *)
	EofHandler = OBJECT
	VAR
		proc : EofProc;
		player : Player;
		alive, dead, called : BOOLEAN;
	
		PROCEDURE Call;
		BEGIN {EXCLUSIVE}
			called := TRUE;
		END Call;
		
		PROCEDURE Terminate;
		BEGIN 
			IF Trace * TraceEof # {} THEN AosOut.String("MediaPlayer: Terminating EOF handler."); AosOut.Ln; END;
			BEGIN {EXCLUSIVE} alive := FALSE; END;
			(* Release obj lock to force condition evaluation *)
			BEGIN {EXCLUSIVE} AWAIT(dead); END;
		END Terminate;
		
		PROCEDURE &New(player : Player);
		BEGIN 
			SELF.player := player; alive := TRUE; dead := FALSE;
		END New;
	
	BEGIN {ACTIVE}
		WHILE alive DO
			BEGIN {EXCLUSIVE} AWAIT(~alive OR called); called := FALSE; END;
			IF alive & (proc # NIL) THEN 
				IF Trace * TraceEof # {} THEN AosOut.String("MediaPlayer: Call EOF procedure."); AosOut.Ln; END;
				proc(player, NIL); 
			END;
		END;
		BEGIN {EXCLUSIVE} dead := TRUE; END;
	END EofHandler;

	(** 
	 * Player Object
	 * The body of the active object manages the state of the player. If a client wants to change the player state, it
	 * issues a state change request using (indirectly) RequestState. 
	 *)
	Player*= OBJECT
	VAR 
		(* Access the fields 'state', 'current' and 'next' only from within exclusive regions! *)
		state : LONGINT;												(* Current state of player *)
		current, next : Context;											
		
		(* State change request fields. Access via RequestState and GetRequestedState. *)
		nextState : LONGINT;
		nextContext : Context;
		requestProcessed : BOOLEAN;
		
		lock : BOOLEAN;
		
		console* : BOOLEAN; (* Should error messages be displayed on console? *)
		
		(* Audio *)				
		soundDevice : AosSound.Driver;									(* Audio Device *)
		mixerChannel, pcmChannel, mChannel : AosSound.MixerChannel;	(* Audio Mixer Channel *) 
		channelName : ARRAY 128 OF CHAR;							(* Audio Mixer Channel Name *) 
					
		(* player window *)						
		pw : PlayerWindow;												(* Video Window *)		
		fullscreen : BOOLEAN;											(* Fullscreen *)
										
		(* Timing *)							
		timer : AosKernel.Timer;
		tickStart : LONGINT;												(* TimeMark Start of Playing *)
		tickDelay : LONGINT;											(* Number of milliseconds the decoding was too slow *)
		lastUpdate : LONGINT;											(* Last time the update procedure was called *)
		videoFramesPlayed : LONGINT;									(* Video Frames played since TimeMarkStart *)
		(* Milliseconds per frame; used for time synchronisation. TODO: Currently, the mspf value of the 'current' context is used.
		what if 'next' context has another mspf value and is concurrently played (transition)? *)
		mspf : LONGINT;		

		(* Delegates *)
		setup* : PROCEDURE {DELEGATE} (data : Setup);											(* init for GUI *)
		update* : PROCEDURE {DELEGATE} (state, pos, maxpos, displayTime: LONGINT);			(* update for GUI *)
		eof : EofHandler;																		(* fired on End of File *)		
		
		(** -- Player Controls ----------------------------------------------- *)
		
		(* Open the given uri *)	
		PROCEDURE Open*(uri : ARRAY OF CHAR; VAR msg : ARRAY OF CHAR; VAR res : LONGINT);
		VAR  context : Context; ignore : LONGINT;
		BEGIN
			context := GetContext(uri, msg, res);
			IF (res # Ok) OR (context = NIL) THEN
				IF Debug OR console THEN 
					AosOut.String("MediaPlayer: Could not open file "); AosOut.String(uri); 
					AosOut.String("(res: "); AosOut.Int(res, 0); AosOut.String(", "); AosOut.String(msg); AosOut.String(")");
					AosOut.Ln;
				END;
				RETURN;
			END;
			RequestState(Ready, context);
			IF Trace * TraceOpen # {} THEN AosOut.String("MediaPlayer: Opened "); AosOut.String(uri); AosOut.Ln; END;
		END Open;

		PROCEDURE Play*;
		BEGIN
			RequestState(Playing, NIL);
		END Play;
		
		(* pos & duration set in number of video frames *)
		PROCEDURE DoTransition*(uri: ARRAY OF CHAR; pos, duration : LONGINT; VAR msg : ARRAY OF CHAR; VAR res : LONGINT);
		VAR context : Context; audioPos : LONGINT; 
		BEGIN 
			IF Trace * TraceTransitions # {} THEN 
				AosOut.String("MediaPlayer: Doing a Transition to "); AosOut.String(uri); AosOut.String(" (Duration: "); 
				AosOut.Int(duration, 0); AosOut.String(" frames)"); AosOut.Ln;
			END;
			IF (duration < 1) OR (pos < 0) THEN 				
				IF Debug OR console THEN AosOut.String("MediaPlayer: Warning: DoTransition: Pos or duration value adjusted."); AosOut.Ln; END;
				IF pos < 0 THEN pos := 0; END;
				IF duration < 1 THEN duration := 1; END;
			END;

			context := GetContext(uri, msg, res);
			IF context = NIL THEN
				IF Debug OR console THEN AosOut.String("MediaPlayer: Could not get context for transition: "); AosOut.String(msg); AosOut.Ln; END;
				RETURN;
			END;
			
			IF context.hasVideo & (pos > context.maxFrames) THEN 
				IF Debug OR console THEN 
					AosOut.String("MediaPlayer: Warning: DoTransition: Pos value clipped to maxFrames: "); 
					AosOut.Int(context.maxFrames, 0); AosOut.Ln; 
				END;
				pos := context.maxFrames;
				(* Continue *)
			END;
			
			IF context.hasVideo THEN
				context.filler.SeekFrame(pos, TRUE, res);
				context.pos := res; context.oldPos := res-1;
				IF context.hasAudio THEN (* search the according Audio *)						
					(* The value 12 corresponds to cdSize in the AVI - WaveFormatStructure - should be given via AosCodecs *)
					audioPos := ENTIER(context.maxTime/10*context.posRate*(res/context.maxFrames) -
						ENTIER(context.maxTime/10*context.posRate*(res/context.maxFrames)) MOD 12);					
					IF audioPos  < 0 THEN audioPos := 0 END;															
				END;	
				
				(* Init Transition *)
				NEW(context.transition); context.transition.Init(context.width, context.height);
				NEW(context.transitionImg); Raster.Create(context.transitionImg, context.width, context.height, Raster.BGR565);
				NEW(context.black); Raster.Create(context.black, context.width, context.height, Raster.BGR565);
				context.transitionFrame := 0;
				context.transitionDuration := duration;
			END;
						
			IF context.hasAudio & (soundDevice # NIL) THEN
				context.audio.SeekSample(audioPos, FALSE, res);
				context.channel.SetVolume(0);
				context.channel.Start;
			END;
			
			IF Trace * TraceTransitions # {} THEN
				AosOut.String("MediaPlayer: Transition to pos (next keyframe): "); AosOut.Int(context.pos, 0);
				AosOut.String(" (wanted: "); AosOut.Int(pos, 0); AosOut.String(")"); AosOut.Ln;
			END;
			RequestState(InTransition, context);			
		END DoTransition;
		
		PROCEDURE Stop*;
		BEGIN
			RequestState(Stopped, NIL);
		END Stop;
		
		PROCEDURE Pause*;
		BEGIN 
			RequestState(Paused, NIL);
		END Pause;
		
		(* Get in  1/10 sec. Returns -1 if information is not available. *)
		PROCEDURE GetPos*(): LONGINT;
		VAR context : Context; res : LONGINT;
		BEGIN {EXCLUSIVE}
			res := -1;
			context := current;
			IF context # NIL THEN
				IF context.hasVideo THEN res := 10*current.filler.GetPos() DIV (1000 DIV current.mspf);
				ELSIF current.hasAudio THEN res := current.audio.GetCurrentTime();
				END;
			END;
			RETURN res;	
		END GetPos;
				
		(* Set position *)
		PROCEDURE SetPos*(pos: LONGINT);
		VAR current : Context;  audioPos, videoPos, res : LONGINT; img : WMGraphics.Image; 
		BEGIN {EXCLUSIVE}
			IF pos < 0 THEN 
				IF Debug THEN AosOut.String("MediaPlayer: Warning: Setpos to "); AosOut.Int(pos, 0); AosOut.String("!?!"); AosOut.Ln; END;  
				pos := 0;
			END;
			current := SELF.current;
			IF (current # NIL) & current.canSeek THEN
				IF current.hasVideo THEN
					IF pos > current.maxFrames THEN 
						IF Debug THEN AosOut.String("MediaPlayer: Warning: Setpos to "); AosOut.Int(pos, 0); AosOut.String(" (>MaxFrames)!?! "); AosOut.Ln; END;  
						pos := current.maxFrames;
					END;
					current.filler.SeekAndGetFrame(pos, img, res);					
					IF img # NIL THEN
						IF pw # NIL THEN pw.ShowFrame(img); END;
					END;
					current.pos := res;
					current.oldPos := current.pos-1;
					IF current.hasAudio THEN (* search the according Audio *)						
						(* The value 12 corresponds to cdSize in the AVI - WaveFormatStructure - should be given via AosCodecs *)
						audioPos := ENTIER(current.maxTime/10*current.posRate*(res/current.maxFrames) -
							ENTIER(current.maxTime/10*current.posRate*(res/current.maxFrames)) MOD 12);					
						IF audioPos  < 0 THEN audioPos := 0 END;		
						current.audio.SeekSample(audioPos, FALSE, res);				
					END;
				ELSIF current.hasAudio THEN	(* search audio only *)
					pos := ENTIER(pos / 10 * current.posRate);		
					current.audio.SeekSample(pos, FALSE, res);
					pos := current.audio.GetCurrentTime();
					current.pos := pos;
					current.oldPos := current.pos-1;
				END;
				(* IF update # NIL THEN update(state, pos, current.maxFrames, pos) END *)	
			END;
		END SetPos;		
		
		PROCEDURE SetEofAction(proc : EofProc);
		BEGIN {EXCLUSIVE}
			IF eof = NIL THEN NEW(eof, SELF); END;
			eof.proc := proc;
		END SetEofAction;
		
		(* Creates a new Player Instance *)
		PROCEDURE &New;
		VAR i : LONGINT;
		BEGIN
			NEW(timer); 
			IF (AosSound.devices.Get("") # NIL) THEN 	
			 	soundDevice := AosSound.GetDefaultDevice();			
				(* set mixerchannel to max output *)
				soundDevice.GetMixerChannel(0, mixerChannel); (* global mixer channel *)
				mixerChannel.SetVolume(255);
				(* find PCM MixerChannel *)
				FOR i := 0 TO soundDevice.GetNofMixerChannels() - 1 DO
					soundDevice.GetMixerChannel(i, mChannel);
					mChannel.GetName(channelName);
					IF channelName = "PCMOut" THEN pcmChannel := mChannel; pcmChannel.SetVolume(255) END
				END;
			END;
			eof := NIL;
			SetState(NotReady);
		END New;
		
		PROCEDURE Acquire;
		BEGIN {EXCLUSIVE}
			AWAIT(lock = FALSE);
			lock := TRUE;
		END Acquire;
		
		PROCEDURE Release;
		BEGIN {EXCLUSIVE}
			lock := FALSE;
		END Release;
		
		(* Request to media player to go into the specified state *)
		PROCEDURE RequestState(state : LONGINT; context : Context);
		BEGIN 
			Acquire;
			BEGIN {EXCLUSIVE}
				requestProcessed := FALSE;
				IF nextState # NoRequest THEN (* Skip the already scheduled state change *)
					IF nextContext # NIL THEN FreeContext(nextContext); END;
				END;
				nextState := state;
				nextContext := context;		
			END;
			(* Release the lock to evaluate the 'nextState' await condition which in turn will
			lead to requestProcessed to be set. *)
			BEGIN {EXCLUSIVE}
				AWAIT(requestProcessed OR (state >= Closed));
			END;
			Release;
		END RequestState;
		
		PROCEDURE GetRequestedState(VAR state : LONGINT; VAR context : Context);
		BEGIN {EXCLUSIVE}
			state := nextState; nextState := NoRequest;
			context := nextContext; nextContext := NIL;
			requestProcessed := TRUE;
		END GetRequestedState;
		
		PROCEDURE SetState(state : LONGINT);
		BEGIN {EXCLUSIVE}
			IF Trace * TraceStates # {} THEN AosOut.String("MediaPlayer: Set state to "); AosOut.Int(state, 0); AosOut.Ln; END;
			SELF.state := state;
		END SetState;
				
		PROCEDURE GetState() : LONGINT;
		BEGIN {EXCLUSIVE}
			RETURN state;
		END GetState; 
						
		PROCEDURE ToggleFullScreen*(sender, data : ANY);
		BEGIN {EXCLUSIVE}
			IF (pw # NIL) & (~ForceFullscreen) THEN pw.ToggleFullscreen; END;
		END ToggleFullScreen; 
		
		PROCEDURE CheckWindow(context : Context);
		VAR oldPw : PlayerWindow;
		BEGIN 
			IF context.hasVideo THEN
				IF (pw # NIL) & pw.fullscreen THEN 
					(* do nothing *)
				ELSIF (pw = NIL) OR (pw.GetWidth() # context.width) OR (pw.GetHeight() # context.height) THEN
					oldPw := pw;
					NEW(pw, context.width, context.height, FALSE, SELF, TRUE);
					IF ForceFullscreen THEN pw.ToggleFullscreen; END;
					IF oldPw # NIL THEN oldPw.Close; END;
				END;
			ELSIF pw # NIL THEN
				pw.Close; 
			END;
		END CheckWindow;
				
		(* reset the tickTimer *)
		PROCEDURE InitTime;
		BEGIN
			 tickStart := AosKernel.GetTimer(); tickDelay := 0;
			videoFramesPlayed := 0;
		END InitTime;
		
		(* Allocate ressources required for playing the audio/video stream *)
		PROCEDURE GetContext(uri : ARRAY OF CHAR; VAR msg : ARRAY OF CHAR; VAR res : LONGINT) : Context;
		VAR 
			in, audioStream, videoStream : AosIO.Reader; 
			demux : AosCodecs.AVDemultiplexer;
			audioDecoder : AosCodecs.AudioDecoder; videoDecoder : AosCodecs.VideoDecoder;
			streamInfo : AosCodecs.AVStreamInfo;
			nofStreams, type, maxFrames, maxTime, width, height, mspf : LONGINT;
			channels, rate, bits, size : LONGINT;
			buffer : AosSound.Buffer;
			hasAudio, hasVideo : BOOLEAN;
			audioCanSeek, videoCanSeek : BOOLEAN;
			name, ext : ARRAY 256 OF CHAR;
			context : Context;
			i : LONGINT;
		BEGIN
			IF Trace * TraceOpen # {} THEN AosOut.String("MediaPlayer: Get decoders for: "); AosOut.String(uri); AosOut.Ln; END;
			in := AosCodecs.OpenInputStream(uri);
			IF (in = NIL) THEN
				res := CouldNotOpenStream; COPY("Can't open stream: ", msg); Utilities.Append(msg, uri);
				IF Debug OR console THEN AosOut.String("MediaPlayer: "); AosOut.String(msg); AosOut.Ln; END;
				RETURN NIL;
			END;
			
			Utilities.GetExtension(uri, name, ext);	(* split uri into name & extension *)
			Utilities.UpperCase(ext);					(* convert extension to UpperCase for AosCodecs *)
			
			(* find Demultiplexer *)
			demux := AosCodecs.GetDemultiplexer(ext);
			IF demux = NIL THEN
				IF Trace * TraceOpen # {} THEN AosOut.String("MediaPlayer: No Demux found: "); AosOut.String(ext); AosOut.Ln; END;
				(* no demuxable file / no suitable demux *)
				audioDecoder := AosCodecs.GetAudioDecoder(ext);
				IF (audioDecoder # NIL) THEN
					audioDecoder.Open(in, res);
					IF (res # AosCodecs.ResOk) THEN
						res := AudioNotCompatible; COPY("Audio stream not compatible: ", msg); Utilities.Append(msg, uri);
						IF Debug OR console THEN AosOut.String("MediaPlayer: "); AosOut.String(msg); AosOut.Ln; END;
						RETURN NIL;
					END;
					hasAudio := TRUE;
					audioCanSeek := audioDecoder.CanSeek();
					IF in IS AosCodecs.FileInputStream THEN (* Set the Stream Length in Bytes, needed for some Functions in some Decoders *)
						audioDecoder.SetStreamLength(in(AosCodecs.FileInputStream).f.Length());
					END;
				ELSE
					videoDecoder := AosCodecs.GetVideoDecoder(ext);
					IF (videoDecoder # NIL) THEN
						videoDecoder.Open(in, res);
						IF (res # AosCodecs.ResOk) THEN
							res := VideoNotCompatible; COPY("Video stream not compatible: ", msg); Utilities.Append(msg, uri);
							IF Debug OR console THEN AosOut.String("MediaPlayer: "); AosOut.String(msg); AosOut.Ln; END;
							RETURN NIL;
						END;													
						hasVideo := TRUE;
						videoCanSeek := videoDecoder.CanSeek();
					ELSE
						res := NoDecoders; COPY("No decoder available for: ", msg); Utilities.Append(msg, uri); 
						IF Debug OR console THEN AosOut.String("MediaPlayer: "); AosOut.String(msg); AosOut.Ln; END;
						RETURN NIL;
					END;
				END;		
			ELSE
				IF Trace * TraceOpen # {} THEN AosOut.String("MediaPlayer: Demux found: "); AosOut.String(ext); AosOut.Ln; END;
				demux.Open(in, res);
				IF (res # AosCodecs.ResOk) THEN
					res := DemuxNotCompatible; COPY("Demux stream not compatible: ", msg); Utilities.Append(msg, uri);
					IF Debug OR console THEN AosOut.String("MediaPlayer: "); AosOut.String(msg); AosOut.Ln; END;
					RETURN NIL;
				END;					
				nofStreams := demux.GetNumberOfStreams();
				IF Trace * TraceOpen # {} THEN AosOut.String("MediaPlayer: Number of Streams: "); AosOut.Int(nofStreams, 0); AosOut.Ln; END;
				FOR i := 0 TO nofStreams-1 DO
					IF Trace * TraceOpen # {} THEN AosOut.String("MediaPlayer: Processing Stream: "); AosOut.Int(i, 0); END;
					type := demux.GetStreamType(i);
					IF Trace * TraceOpen # {}  THEN AosOut.String(" with Type: "); AosOut.Int(type, 0); AosOut.Ln; END;
					IF (type = AosCodecs.STVideo) THEN (* Video Stream *)
						videoStream := demux.GetStream(i);
						videoStream(AosCodecs.DemuxStream).Open(demux, i);
						streamInfo := demux.GetStreamInfo(i);
						videoDecoder := AosCodecs.GetVideoDecoder(streamInfo.contentType);
						IF (videoDecoder = NIL) THEN
							res := NoVideoDecoder; COPY("No Decoder for video format: ", msg); Utilities.Append(msg, streamInfo.contentType);
							IF Debug OR console THEN AosOut.String("MediaPlayer: "); AosOut.String(msg); AosOut.Ln; END;
							hasVideo := FALSE;					
						ELSE
							videoDecoder.Open(videoStream, res);
							IF (res # AosCodecs.ResOk) THEN
								res := VideoNotCompatible; COPY("Video stream not compatible: ", msg); Utilities.Append(msg, uri);
								IF Debug OR console THEN AosOut.String("MediaPlayer: "); AosOut.String(msg); AosOut.Ln; END;
								hasVideo := FALSE;
							ELSE
								videoCanSeek := videoDecoder.CanSeek();
								maxFrames := streamInfo.frames;
								IF streamInfo.rate # 0 THEN maxTime := 10 * streamInfo.frames DIV streamInfo.rate; (* 1/10 sec *)
								ELSE videoCanSeek := FALSE;
								END;
								hasVideo := TRUE;
							END;							
						END;
					ELSIF (type = AosCodecs.STAudio) THEN (* Audio Stream *)
						audioStream := demux.GetStream(i);
						audioStream(AosCodecs.DemuxStream).Open(demux, i);
						streamInfo := demux.GetStreamInfo(i);
						audioDecoder := AosCodecs.GetAudioDecoder(streamInfo.contentType);
						IF (audioDecoder = NIL) THEN
							res := NoAudioDecoder; COPY("No Decoder for audio format: ", msg); Utilities.Append(msg, streamInfo.contentType);
							IF Debug OR console THEN AosOut.String("MediaPlayer: "); AosOut.String(msg); AosOut.Ln; END;
							hasAudio := FALSE;				
						ELSE
							audioDecoder.Open(audioStream, res);	
							IF (res # AosCodecs.ResOk) THEN
								res := AudioNotCompatible; COPY("Audio stream not compatible: ", msg); Utilities.Append(msg, uri);
								IF Debug OR console THEN AosOut.String("MediaPlayer: "); AosOut.String(msg); AosOut.Ln; END;
								hasAudio := FALSE; 
							ELSE
								audioCanSeek := audioDecoder.CanSeek();
								hasAudio := TRUE; 
							END;							
						END;								
					ELSE
						IF Trace * TraceOpen # {} THEN AosOut.String("MediaPlayer: Unknown Stream Type: "); AosOut.Int(type, 0); AosOut.Ln; END;
					END;
				END;
			END;
			
			IF hasVideo OR hasAudio THEN
				NEW(context);
				COPY(uri, context.uri);
				IF hasVideo THEN
					context.hasVideo := TRUE; 
					context.video := videoDecoder;
					context.maxFrames := maxFrames; context.maxTime := maxTime;
					videoDecoder.GetVideoInfo(width, height, mspf);
					context.width := width; context.height := height; context.mspf := mspf;
					NEW(context.filler, width, height, videoDecoder);
				END;
				IF hasAudio & (soundDevice # NIL)THEN
					context.hasAudio := TRUE; 
					context.audio := audioDecoder;
										
					(* Calculate delay induced by audio buffering *)					
					IF (channels # 0) & (bits # 0) & (rate # 0) THEN
						context.delay := ENTIER(AudioBuffers * AudioBufferSize * 8 (* Buffersize in bits *) / (channels * bits * rate) (* bit rate of audio stream *)) + 1 ;
					ELSE
						context.delay := 50; (* guess *)
					END;
					context.delay := context.delay + AudioConstantDelay;
					IF Trace * TraceOpen # {} THEN AosOut.String("Audio delay: "); AosOut.Int(context.delay, 0); AosOut.String("ms"); AosOut.Ln; END;

					NEW(context.bufferpool, AudioBuffers);
					FOR i := 0 TO AudioBuffers-1 DO
						NEW(buffer); buffer.len := AudioBufferSize; NEW(buffer.data, AudioBufferSize);
						context.bufferpool.Add(buffer);
					END;
					audioDecoder.GetAudioInfo(channels, rate, bits);
					context.channels := channels; context.rate := rate; context.bits := bits;
					
					(* UGLY: AVStreamInfo reports different rate as GetAudioInfo does. *)
					IF (audioStream # NIL) & (audioStream IS AosCodecs.DemuxStream) THEN
						context.posRate := audioStream(AosCodecs.DemuxStream).streamInfo.rate;
					END;
					
					IF ~hasVideo THEN
						context.maxTime := audioDecoder.GetTotalSamples() DIV rate * 10;
						context.maxFrames := maxTime;
					END;
					audioDecoder.SeekSample(0, FALSE, res);(* what if stream not seekable? *)
					soundDevice.OpenPlayChannel(context.channel, rate, bits, channels, AosSound.FormatPCM, res);
					IF context.channel = NIL THEN
						IF Debug OR console THEN AosOut.String("MediaPlayer: Could not open audio play channel."); AosOut.Ln; END;
					ELSE
						context.channel.RegisterBufferListener(context.bufferpool.Add);
						context.channel.SetVolume(255);			
					END;
				END;			
				context.canSeek := (~hasVideo OR videoCanSeek) & (~hasAudio OR audioCanSeek);
			ELSE
				res := NoDecoders; COPY("No demux/decoder found for ", msg); Utilities.Append(msg, uri);
				IF Debug OR console THEN AosOut.String("MediaPlayer: "); AosOut.String(msg); AosOut.Ln; END;
			END;
			IF Trace * TraceOpen # {} THEN
				AosOut.String("Context opened: Maxtime: "); AosOut.Int(context.maxTime, 0); 
				AosOut.String(", maxFrames: "); AosOut.Int(context.maxFrames, 0); AosOut.Ln;
			END;
			RETURN context;									
		END GetContext;
		
		PROCEDURE FreeContext(context : Context);
		BEGIN
			IF context # NIL THEN
				IF context.filler # NIL THEN context.filler.Close; context.filler := NIL; END;
				IF context.channel # NIL THEN context.channel.Close; context.channel := NIL; END;
			END;
		END FreeContext;
					
		PROCEDURE Loop(sender, data: ANY);
		BEGIN
			IF Trace * TraceEof # {} THEN AosOut.String("MediaPlayer: EOF Loop."); AosOut.Ln; END;
			Stop; Play;
		END Loop;
		
		PROCEDURE Quit(sender, data: ANY);
		BEGIN
			IF Trace * TraceEof # {} THEN AosOut.String("MediaPlayer: EOF Quit."); AosOut.Ln; END;
			Close;
		END Quit;	
		
		PROCEDURE RenderAudio(c :  Context);
		BEGIN (* no concurrency allowed *)
			ASSERT(c # NIL);
			WHILE c.hasAudio & c.audio.HasMoreData() & (c.bufferpool.NofBuffers() > 0) DO
				c.aBuffer := c.bufferpool.Remove();
				c.audio.FillBuffer(c.aBuffer);
				c.channel.QueueBuffer(c.aBuffer);
				IF ~c.hasVideo THEN
					c.pos := c.audio.GetCurrentTime();
				END
			END;
		END RenderAudio;
		
		(* Render the next video frame of the specified context *)
		PROCEDURE RenderVideo(c : Context);
		BEGIN
			ASSERT((c # NIL) & (c.hasVideo));
			c.vBuffer := c.filler.GetNextBuffer();
			IF pw # NIL THEN pw.ShowFrame(c.vBuffer) END;
			c.filler.ReturnBuffer(c.vBuffer);	
			INC(videoFramesPlayed); c.oldPos := c.pos; INC(c.pos);			
		END RenderVideo;
		
		(* Render transition from context 'from' to context 'to' *)
		PROCEDURE RenderVideoTransition(from, to : Context);
		VAR temp : VideoBuffer;
		BEGIN
			ASSERT((to # NIL) & (to.transition # NIL) & (to.transitionImg # NIL) & (to.black # NIL));
			INC(to.transitionFrame);
			IF Trace * TraceTransitions # {} THEN 
				AosOut.String("MediaPlayer: Transition Frame "); 
				AosOut.Int(to.transitionFrame, 0); AosOut.String(" of "); AosOut.Int(to.transitionDuration, 0);
				AosOut.Ln;
			END;
			(* stop filler if enough frames already precalced in buffer *)
			IF (from # NIL) THEN
				IF from.filler.NofFullBuffers() >= (to.transitionDuration - to.transitionFrame) THEN from.filler.Stop; END;  
				from.vBuffer := from.filler.GetNextBuffer();
				temp := from.vBuffer;
			ELSE
				temp := to.black; 
			END;
			(* display frame *)
			to.vBuffer := to.filler.GetNextBuffer();
			to.transition.CalcImage(temp, to.vBuffer, to.transitionImg, to.transitionFrame*255 DIV to.transitionDuration);
			IF pw # NIL THEN pw.ShowFrame(to.transitionImg) END;
			
			to.filler.ReturnBuffer(to.vBuffer);				
			to.oldPos := to.pos; INC(to.pos);
			IF from # NIL THEN 
				from.filler.ReturnBuffer(from.vBuffer);
				from.oldPos := from.pos; INC(from.pos);
			END;
			INC(videoFramesPlayed); 
			IF to.transitionFrame >= to.transitionDuration THEN
				IF (from # NIL) THEN FreeContext(from); from := NIL; END; 
				IF Trace * TraceTransitions # {} THEN AosOut.String("MediaPlayer: Transition Finished."); AosOut.Ln; END;
			 END;
		END RenderVideoTransition;
		
		(* Render video and/or audio *)
		PROCEDURE Render(c1, c2 : Context);
		VAR 
			tickIs: LONGINT; 
			tickShould : LONGINT;											
		BEGIN
			IF c1 # NIL THEN
				IF GetState() = InTransition THEN (* Render transition from c2 to c1 *)
					IF c2 # NIL THEN
						IF c2.hasAudio THEN	
							RenderAudio(c2); 
							c2.channel.SetVolume(256 - c1.transitionFrame*(256 DIV c1.transitionDuration));
						ELSE
							timer.Sleep(40);
						END;
					END;
					IF c1.hasAudio THEN 
						RenderAudio(c1); 
						c1.channel.SetVolume(256*c1.transitionFrame DIV c1.transitionDuration);
					END;
					IF c1.hasVideo THEN RenderVideoTransition(c2, c1); END;
				ELSE
					IF c1.hasAudio THEN
						RenderAudio(c1);
					END;
					IF c1.hasVideo THEN
						RenderVideo(c1);
					END;
				END;
			END;	
			(* Check time and sleep or drop frames *)
			tickIs := AosKernel.GetTimer() - tickStart;
			tickShould := videoFramesPlayed * mspf;
			IF tickIs < tickShould THEN (* We were too fast *)
				timer.Sleep(tickShould-tickIs);
			END;
	
			IF Trace * TraceRendering # {} THEN
				AosOut.String("Frame: "); AosOut.Int(videoFramesPlayed, 0);
				AosOut.String(" [Is: "); AosOut.Int(tickIs, 0); AosOut.String(", Should="); AosOut.Int(tickShould, 0);
				AosOut.String(",Sleep: ");  
				IF (tickIs < tickShould) THEN 
					IF tickDelay < (tickShould-tickIs) THEN 
						AosOut.Int(tickShould - tickIs - tickDelay, 0); 
					ELSE
						AosOut.Int(8, 0);
					END;
				ELSE AosOut.Int(0, 0);
				END;				
				AosOut.String(", Delay: "); AosOut.Int(tickDelay, 0); 
				AosOut.String("]"); AosOut.Ln;
			END;
		END Render;
			
		PROCEDURE Close*;
		BEGIN 
			RequestState(Closed, NIL);
			BEGIN {EXCLUSIVE} AWAIT(state = Closed); END;
			mplayer := NIL;
			IF Trace * TracePlayer # {} THEN AosOut.String("MediaPlayer closed."); AosOut.Ln; END;
		END Close;
		
		PROCEDURE StopIntern;
		VAR img : WMGraphics.Image; res : LONGINT;
		BEGIN 
			FreeContext(next); next := NIL;
			IF current # NIL THEN
				IF current.hasVideo THEN current.filler.SeekAndGetFrame(0, img, res); END;
				IF current.hasAudio THEN current.channel.Stop; current.audio.SeekSample(0, FALSE, res); END;
				current.pos := 0; current.oldPos := -1;
			END;
			IF pw # NIL THEN 
				IF img # NIL THEN pw.ShowFrame(img); ELSE pw.ShowBlack; END;
			END;
		END StopIntern;
				
		PROCEDURE StartPlayIntern;
		VAR res : LONGINT;
		BEGIN
			IF current # NIL THEN
				IF state = Finished THEN 
					current.pos := 0; current.oldPos := -1;			
					IF current.hasVideo THEN current.filler.SeekFrame(0, TRUE, res); END;
					IF current.hasAudio THEN current.channel.Stop; current.audio.SeekSample(0, FALSE, res); END;		
				END;
				IF current.hasAudio THEN current.channel.SetVolume(255); current.channel.Start; END;
				InitTime;
			END;
		END StartPlayIntern;
		
		(* Pause the current and next context if applicable *)
		PROCEDURE PauseIntern;
		BEGIN
			IF (current # NIL) & current.hasAudio THEN current.channel.Pause; END;
			IF (next # NIL) & next.hasAudio THEN next.channel.Pause; END;
		END PauseIntern;
		
		(* Resume playing the curent and next context that are paused *)
		PROCEDURE ResumeIntern;
		VAR audioPos, res : LONGINT;
		BEGIN
			IF (current # NIL) THEN
				IF current.hasVideo THEN
					res := (current.video.GetCurrentFrame()-current.filler.NofFullBuffers());
					IF current.hasAudio THEN		
						audioPos := ENTIER(current.maxTime/10*current.posRate*(res/current.maxFrames) -
							ENTIER(current.maxTime/10*current.posRate*(res/current.maxFrames)) MOD 12);
						IF audioPos  < 0 THEN audioPos := 0 END;		
						current.audio.SeekSample(audioPos, FALSE, res);
					END;
				END;
				IF current.hasAudio THEN current.channel.Start; END;
			END;		
			IF (next # NIL) THEN
				IF next.hasVideo THEN
					res := (next.video.GetCurrentFrame()-next.filler.NofFullBuffers());
					IF next.hasAudio THEN		
						audioPos := ENTIER(next.maxTime/10*next.posRate*(res/next.maxFrames) -
							ENTIER(next.maxTime/10*next.posRate*(res/next.maxFrames)) MOD 12);
						IF audioPos  < 0 THEN audioPos := 0 END;		
						next.audio.SeekSample(audioPos, FALSE, res);
					END;
				END;
				IF next.hasAudio THEN next.channel.Start; END;
			END;		
			IF (current # NIL) OR (next # NIL) THEN
				InitTime;
			END;
		END ResumeIntern;
		
		PROCEDURE OpenIntern(nextContext : Context);
		VAR img : WMGraphics.Image; data : Setup; res : LONGINT;
		BEGIN
			FreeContext(next); next := NIL;
			FreeContext(current); current := nextContext; 
			mspf := current.mspf; current.pos := 0; current.oldPos := -1;
			CheckWindow(current);
			IF current.hasVideo THEN 
				current.filler.SeekAndGetFrame(0, img, res);	
			END;
			IF pw # NIL THEN 
				IF img # NIL THEN pw.ShowFrame(img); ELSE pw.ShowBlack; END;
			END;
			IF setup # NIL THEN 
				NEW(data);
				data.hasVideo := current.hasVideo; 
				data.hasAudio := current.hasAudio;
				data.canSeek := current.canSeek;
				COPY(nextContext.uri, data.uri);
				data.mspf := current.mspf;
				data.maxFrames := current.maxFrames;
				data.maxTime := current.maxTime;
				IF current.hasVideo THEN
					data.width := current.width; data.height := current.height;
				END;
				IF current.hasAudio THEN
					data.channels := current.channels; data.bits := current.bits; data.rate := current.rate;
				END;
				setup(data); 
			END;
		END OpenIntern;
						
		PROCEDURE IsValidStateTransition(from, to : LONGINT) : BOOLEAN;
		VAR res : BOOLEAN;
		BEGIN
			res := FALSE;
			CASE from OF				
				|NotReady:		IF (to = Ready) OR (to = InTransition) THEN res := TRUE; END;
				|Ready:			IF (to = Ready) OR (to = Playing) OR (to = InTransition) THEN res := TRUE; END;
				|Playing:		IF (to = Ready) OR (to = Paused) OR (to = Stopped) OR (to = InTransition) THEN res := TRUE; END;
				|Paused:		IF (to = Ready) OR (to = Playing) OR (to = Stopped) OR (to = Paused) OR (to = InTransition) THEN res := TRUE; END;
				|Stopped:		IF (to = Ready) OR (to = Playing) OR (to = InTransition) THEN res := TRUE; END;
				|Finished:		IF (to = Ready) OR (to = Playing) OR (to = Stopped) OR (to = InTransition) THEN res := TRUE; END;
				|InTransition:	IF (to = Ready) OR (to = Paused) OR (to = Stopped) OR (to = InTransition) THEN res := TRUE; END;
				|Error: 			(* Do not execute commands anymore *)
				|Closed:  		(* Do not execute commands anymore *)
			ELSE
				IF Debug THEN AosOut.String("MediaPlayer: Start state of state transition not known."); AosOut.Ln; END;
			END;
			IF (to = Error) OR (to = Closed)  THEN res := TRUE; END;
			RETURN res;
		END IsValidStateTransition;
		
		(* Pre-Condition: (state = Playing) OR (state = InTransition) OR (nextState # NoRequest) *)
		PROCEDURE EvaluateState;
		VAR
			oldState : LONGINT; 
			isValid : BOOLEAN; nextState : LONGINT; nextContext : Context;
			audioFinished, videoFinished : BOOLEAN; 
			currentTime : LONGINT; callUpdate : BOOLEAN;
			temp : LONGINT;
		BEGIN
			GetRequestedState(nextState, nextContext); oldState := state;
			IF (nextState # NoRequest) THEN
				isValid :=  IsValidStateTransition(state, nextState);
				IF isValid THEN 
					CASE nextState OF
						NoRequest: (* Rest in current state *)
						|Ready: (* Abort whatever the player is doing and go to 'Ready' state *)
							OpenIntern(nextContext);
							SetState(Ready);
						|Playing:
							StartPlayIntern; SetState(Playing);
						|Paused:
							IF state = Paused THEN
								ResumeIntern; SetState(Playing);
							ELSE
								PauseIntern; SetState(Paused); 
							END;
						|Stopped:
							StopIntern; SetState(Stopped);
						|InTransition: 
							FreeContext(next); next := current; 
							current := nextContext;
							mspf := current.mspf;
							CheckWindow(current);
							InitTime;
							SetState(InTransition);
						|Closed:
							FreeContext(current); current := NIL;
							FreeContext(next); next := NIL;
							FreeContext(nextContext); nextContext := NIL;
							SetState(Closed);
					ELSE 
						IF Debug THEN AosOut.String("MediaPlayer: Warning: Ignore request to set state to: "); AosOut.Int(nextState, 0); AosOut.Ln; END;
					END;
				END;
				IF Trace * TraceStates # {} THEN
					AosOut.String("MediaPlayer: Request state transition from '"); 
					AosOut.Int(oldState, 0); AosOut.String("' to '"); AosOut.Int(nextState, 0);	AosOut.String("': "); 
					IF isValid THEN AosOut.String("Valid (New state: "); AosOut.Int(state, 0); AosOut.String(")"); 
					ELSE AosOut.String("Invalid (Rejected)"); 
					END;
					AosOut.Ln;
				END;
			END;
			
			IF nextState = NoRequest THEN (* Check whether current video is still playing *)
				IF (state = InTransition) & (current.transitionFrame >= current.transitionDuration) THEN (* Transition Finished *)
					SetState(Playing);
				END;
				audioFinished := FALSE; videoFinished := FALSE;
				IF current = NIL THEN
					audioFinished := TRUE; videoFinished := TRUE;
				ELSE
					IF ~current.hasVideo OR (current.hasVideo & ~current.video.HasMoreData() & (current.filler.NofFullBuffers() <= 0)) THEN videoFinished := TRUE; END;
					IF ~current.hasAudio OR (current.hasAudio & ~current.audio.HasMoreData()) THEN audioFinished := TRUE; END;
					IF Debug THEN
					(*	IF (current.hasVideo = current.hasAudio) & (videoFinished # audioFinished) THEN
							AosOut.String("MediaPlayer: Audio & Video not finished at the same time."); AosOut.Ln;
						END; *)
					END;
				END;
				IF (current = NIL) OR ((current # NIL) & current.hasVideo & videoFinished) OR ((current # NIL) & (~current.hasVideo) & audioFinished) THEN				
					IF state # Finished THEN
						IF Trace * TracePlayer # {} THEN 
							AosOut.String("MediaPlayer: Finished playing: "); 
							IF (current = NIL) THEN AosOut.String("No context."); 
							ELSE
								IF videoFinished THEN AosOut.String("[Video finished]"); END;
								IF audioFinished THEN AosOut.String("[Audio finished]"); END;
							END;
							AosOut.Ln;
						END;
						IF eof # NIL THEN eof.Call; END;
					END;
					SetState(Finished);
				END
			END;
			IF current # NIL THEN
				IF current.hasVideo THEN
					currentTime := 10*current.pos DIV (1000 DIV current.mspf);
				ELSE
					currentTime := current.audio.GetCurrentTime(); 
				END;
				temp := AosKernel.GetTimer();
				callUpdate := (update # NIL) & ((state = Finished) OR (nextState # NoRequest) OR (temp - lastUpdate >= UpdateInterval));
				IF callUpdate THEN lastUpdate := temp; update(state, current.pos, current.maxFrames, currentTime); END;
			ELSE
				IF update # NIL THEN update(state, 0, 0, 0); END;
			END;				
		END EvaluateState;
					
	BEGIN {ACTIVE}
		WHILE state < Closed DO		
			(* Synchronization to player commands *)
			BEGIN {EXCLUSIVE} AWAIT((state = Playing) OR (state = InTransition) OR (state >= Closed) OR (nextState # NoRequest)); END;
			IF state < Closed THEN 
				(* Within this IF statement we have exlusive access to all Context objects *)
				(* Render next video/audio frame *)
				IF nextState = NoRequest THEN Render(current, next); END; 
				(* State management (process state change requests and current state *)
				EvaluateState;
			END;
		END;
	FINALLY
		FreeContext(current); current := NIL;
		FreeContext(next); next := NIL;
		FreeContext(nextContext); nextContext := NIL;
		IF eof # NIL THEN eof.Terminate; END;
		IF pw # NIL THEN pw.Close; pw := NIL; END;
		SetState(Closed);
	END Player;
	
VAR mplayer : Player;

(** Command line user interface *)

(** Play the specified video/audio file *)
PROCEDURE Open*(par : ANY) : ANY; (** <filename> ~ *)
VAR 
	s : AosCommands.Parameters; sr : AosIO.StringReader;
	filename, msg : ARRAY 256 OF CHAR;
	res : LONGINT;
BEGIN {EXCLUSIVE}
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^); sr.String(filename);
	IF mplayer = NIL THEN NEW(mplayer); END;
	mplayer.Open(filename, msg, res);
	IF res = AosIO.Ok THEN 
		mplayer.Play; 
	ELSE
		AosOut.String("MediaPlayer: Could not open file: "); AosOut.String(filename); 
		AosOut.String(" (res: "); AosOut.Int(res, 0); AosOut.String(", "); AosOut.String(msg); AosOut.String(")"); AosOut.Ln; 
	END;
	RETURN NIL
END Open;

(** Do a transition to the specified video/audio file (of the specified duration) *)
PROCEDURE TransitionTo*(par : ANY) : ANY; (** <filename> [transitionDuration] ~ *)
VAR 
	s : AosCommands.Parameters; sr : AosIO.StringReader;
	filename, msg : ARRAY 256 OF CHAR;
	duration : LONGINT;
	res : LONGINT;
BEGIN {EXCLUSIVE}
	s := par(AosCommands.Parameters);
	NEW(sr, LEN(s.str^)); sr.Set(s.str^); sr.String(filename);
	sr.SkipWhitespace; sr.Int(duration, FALSE);
	IF (sr.res # AosIO.Ok) OR (duration < 1) THEN duration := 25; END;
	IF mplayer # NIL THEN
		mplayer.DoTransition(filename, 0, duration, msg, res);
		IF res # Ok THEN 
			AosOut.String("MediaPlayer.DoTransition Error (res: "); AosOut.Int(res, 0); 
			AosOut.String(", "); AosOut.String(msg); AosOut.String(")"); AosOut.Ln;
		END;
	ELSE
		NEW(mplayer); mplayer.DoTransition(filename, 0, duration, msg, res);
		IF res # Ok THEN 
			AosOut.String("MediaPlayer.DoTransition Error (res: "); AosOut.Int(res, 0); 
			AosOut.String(", "); AosOut.String(msg); AosOut.String(")"); AosOut.Ln;
		END;
	END;	
	RETURN NIL
END TransitionTo;

(** Close the media player and its window *)
PROCEDURE Close*(par : ANY) : ANY; (** ~ *)
BEGIN
	Cleanup;
	RETURN NIL;
END Close;

(** Set a EOF (end of file) handler, i.e. action to be taken when playing of a ressource finished. *)
PROCEDURE SetEofAction*(par : ANY) : ANY; (* [none | loop | quit] ~ *)
VAR s : AosCommands.Parameters; sr : AosIO.StringReader; command : ARRAY 32 OF CHAR;
BEGIN
	IF mplayer # NIL THEN
		s := par(AosCommands.Parameters);
		NEW(sr, LEN(s.str^)); sr.Set(s.str^); sr.String(command);
		IF Utilities.Match("none", command) THEN
			mplayer.eof := NIL;
			AosOut.String("MediaPlayer: Set EOF to NIL.");
		ELSIF Utilities.Match("loop", command) THEN 
			mplayer.SetEofAction(mplayer.Loop);
			AosOut.String("MediaPlayer: Set EOF to Loop."); 
		ELSIF Utilities.Match("quit", command) THEN
			mplayer.SetEofAction(mplayer.Quit);
			AosOut.String("MediaPlayer: Set EOF to Quit."); 
		ELSE
			AosOut.String("MediaPlayer: Command not recognized.");
		END;
	ELSE
		AosOut.String("MediaPlayer: Cannot set EOF - player not running."); AosOut.Ln;
	END;
	AosOut.Ln;
	RETURN NIL
END SetEofAction;

PROCEDURE Cleanup;
BEGIN {EXCLUSIVE}
	IF mplayer # NIL THEN mplayer.Close; mplayer := NIL; END;
END Cleanup;

BEGIN
	AosModules.InstallTermHandler(Cleanup);
END MediaPlayer.

------------------------------------------------------------
Aosi810Sound.Install ~
S.Free MediaPlayer ~
S.Free WMPlayer MediaPlayer AosDivXDecoder DivXHelper DivXTypes AVI~
PC0.Compile AVI.Mod DivXTypes.Mod DivXHelper.Mod AosDivXDecoder.Mod MediaPlayer.Mod WMPlayer.Mod~

S.Free WMPlayer MediaPlayer ~

WMPlayer.Open flags.avi~

MediaPlayer.Open flags.avi~

MediaPlayer.TransitionTo flags.avi 25 ~

MediaPlayer.TransitionTo flags.avi 300 ~

MediaPlayer.Close ~ 

MediaPlayer.SetEofAction none ~
MediaPlayer.SetEofAction loop ~
MediaPlayer.SetEofAction quit ~

