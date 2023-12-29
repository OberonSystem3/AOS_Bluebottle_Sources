MODULE W3dAbstractWorld;	(** AUTHOR "TF"; PURPOSE "Abstract 3d world (case study)"; *)

IMPORT
	Vectors := W3dVectors, Matrix := W3dMatrix, Raster;

TYPE
	Vertex* = OBJECT
		(** SetPos - set the position of the vertex to p *)
		PROCEDURE SetPos*(p : Vectors.TVector3d);
		BEGIN 
		END SetPos;
		
		(** SetUV - set the relative texture position of this vertex (texture is defined in the triangle) *)
		PROCEDURE SetUV*(u, v : LONGREAL);
		BEGIN
		END SetUV;
	END Vertex;
	
	Texture* = OBJECT
	
	END Texture;
	
	Object* = OBJECT
		(** SetIndex - index that will be reported by World.GetOwnerIndex(x, y) if the object is visible in the view at the pixel(x, y) *)
		PROCEDURE SetIndex*(idx : LONGINT);
		BEGIN
		END SetIndex;
	
		(** convert an image to the internal texture format of the Object *)
		PROCEDURE AddTexture*(img : Raster.Image) : Texture;
		BEGIN
		END AddTexture;
		
		(** convert a vector to the internal vertex format of the object *)
		PROCEDURE AddVertex*(p : Vectors.TVector3d) : Vertex;
		BEGIN
		END AddVertex;
		
		PROCEDURE AddTriangle*(a, b, c : Vertex; color : LONGINT; tex : Texture; mask0, culled: BOOLEAN);
		BEGIN
		END AddTriangle;
		
		PROCEDURE Clear*;
		BEGIN
		END Clear;
	END Object;
	
	World* = OBJECT
		PROCEDURE CreateObject*() : Object;
		BEGIN
		END CreateObject;
		
		PROCEDURE AddObject*(x : Object);
		BEGIN
		END AddObject;
		
		(** replace one object by another (atomic) *)
		PROCEDURE ReplaceObject*(x, y: Object);
		BEGIN
		END ReplaceObject;
		
		(** Declare if an object is animated. Some renderers can optimize the situation of a static world with
			a few animated objects *) 
		PROCEDURE SetAnimated*(obj : Object; animated: BOOLEAN);
		BEGIN
		END SetAnimated;
		
		PROCEDURE Clear*;
		BEGIN
		END Clear;
		
		PROCEDURE SetCamera*(p, d, u : Vectors.TVector3d);
		BEGIN
		END SetCamera;
		
		PROCEDURE Render*(img : Raster.Image; movingOnly : BOOLEAN);
		BEGIN
		END Render;
		
		(** currently not for animated objects :-( *) 
		PROCEDURE GetOwnerIndex*(x, y : LONGINT): LONGINT;
		BEGIN
		END GetOwnerIndex;
	END World;
	
END W3dAbstractWorld.
 