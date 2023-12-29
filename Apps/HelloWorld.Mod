MODULE HelloWorld;

IMPORT
	AosOut;

PROCEDURE Hello*(par : ANY) : ANY;
BEGIN
	AosOut.String("Hello"); AosOut.Ln; 
	RETURN NIL
END Hello;

PROCEDURE HelloCn*(par : ANY) : ANY;
BEGIN
	AosOut.String("你好"); AosOut.Ln;
	RETURN NIL
END HelloCn;

PROCEDURE HelloKr*(par : ANY) : ANY;
BEGIN
	AosOut.String("여보세요"); AosOut.Ln; 
	RETURN NIL
END HelloKr;

PROCEDURE HelloJp*(par : ANY) : ANY;
BEGIN
	AosOut.String("こんにちは"); AosOut.Ln; 
	RETURN NIL
END HelloJp;

PROCEDURE HelloRu*(par : ANY) : ANY;
BEGIN
	AosOut.String("привет"); AosOut.Ln; 
	RETURN NIL
END HelloRu;

END HelloWorld.

S.Free HelloWorld ~
HelloWorld.Hello ~
HelloWorld.HelloCn ~
HelloWorld.HelloKr ~
HelloWorld.HelloJp ~ 
HelloWorld.HelloRu ~
 

