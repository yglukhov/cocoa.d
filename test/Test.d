
import std.stdio;
import cocoa;

mixin(_ObjC!q{

extern (C) void* testFunc()
{
	writeln("Test func called!");
	void* result = [ObjC.NSString stringWithString: "Hello, World!"];
	return result;
}

});
