
import cocoa;
import std.stdio;

class AppDelegate : ObjC.NSObject
{
	mixin RegisterObjCClass;

	this()
	{
		writeln(__FUNCTION__);
	}

	~this()
	{
		writeln(__FUNCTION__);
	}

	void applicationDidFinishLaunching_(id notification)
	{
		writeln("applicationDidFinishLaunching");
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
