
import cocoa;
import std.stdio;

class AppDelegate : ObjC.NSObject
{
	mixin RegisterObjCClass;

	this()
	{
		writeln("AppDelegate::ctor");
	}

	void applicationDidFinishLaunching_(id notification)
	{
		writeln("applicationDidFinishLaunching_123");
	}

	void doSomething()
	{
		writeln("doSomething123");
	}

	void setWindow_(CFTypeRef wnd)
	{
		_window = wnd;
	}

	CFTypeRef window()
	{
		return _window;
	}

	CFTypeRef _window;
}
