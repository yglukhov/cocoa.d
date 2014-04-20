
import cocoa;
import std.stdio;
import core.memory;

extern (C) void NSRectFill(Cocoa.NSRect rect);


class DView : ObjC.NSView
{
	mixin RegisterObjCClass;

	this()
	{
		writeln(__FUNCTION__);
	}

	this(int a)
	{
		writeln(__FUNCTION__);
	}

	void drawRect_(Cocoa.NSRect rect)
	{
		mixin(_ObjC!q{

		[[ObjC.NSColor.c redColor] set];
		NSRectFill(rect);

		});
	}

	void testMethod_andArg_(Cocoa.NSRect rect, int b)
	{
		writeln("testMethod ", rect, " ", b);
	}
}
