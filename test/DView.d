
import cocoa;
import std.stdio;
import core.memory;

extern (C) void NSRectFill(Cocoa.NSRect rect);


class DView : ObjC.OView
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

		[super drawRect: rect];
		rect = Cocoa.NSInsetRect(rect, 10, 10);
		[[ObjC.NSColor redColor] set];
		NSRectFill(rect);

		});
	}

	void testMethod_andArg_(Cocoa.NSRect rect, int b)
	{
		writeln("testMethod ", rect, " ", b);
	}
}
