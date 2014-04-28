#!/usr/bin/env rdmd -debug -unittest -main

/*******************************************************************************
 * This module implements D to Objective-C bridge. It is designed to work with
 * any Objective-C library or framework without any other explicit bindings.
 *
 * Synopsis:
 * -----

// Calling Objective-C code:
mixin(_ObjC!q{
	ObjC.NSString oStr = [ObjC.NSString stringWithFormat: "%d, %.2f, %d", 12, 34.56, 78];
	string dStr = [oStr description];
	assert(dStr == "123, 34.56, 78");

	id array = [ObjC.NSArray arrayWithObjects: "Hello", "world", null];
	dStr = [array componentsJoinedByString: ", "];
	assert(dStr == "Hello, world");
});

extern (C) void NSRectFill(Cocoa.NSRect rect);

// Subclassing Objective-C classes:
class DView : ObjC.NSView
{
	mixin RegisterObjCClass;
	void drawRect_(Cocoa.NSRect rect)
	{
		mixin(_ObjC!q{
			[[NSColor redColor] set];
			NSRectFill(rect);
		});
	}
}

 * -----
 *
 ******************************************************************************/
module cocoa;

import std.stdio;
import core.sys.posix.dlfcn;
import std.array;
import std.string;
public import std.traits;
import std.conv;
import std.variant;
import std.ascii;
import core.stdc.string;
import core.stdc.config;
import core.memory;
import std.range;
import std.c.stdlib;
import std.exception;


pragma(lib, "objc");

extern (C)
{
	alias SEL = immutable(void)*;
	alias _ObjCClass = immutable(void)*;
	alias Class = immutable(void)*;
	alias Method = const(void)*;
	alias CFTypeRef = const(void)*;
	alias CFStringRef = CFTypeRef;
	alias CFAllocatorRef = CFTypeRef;
	alias CFArrayRef = CFTypeRef;
	alias UInt8 = ubyte;
	alias CFIndex = c_long;
	alias uint8_t = ubyte;
	alias Boolean = ubyte;
	alias BOOL = ubyte;
	alias IMP = immutable(void)*;

	enum CFStringEncoding : uint
	{
	    kCFStringEncodingMacRoman = 0,
	    kCFStringEncodingWindowsLatin1 = 0x0500, /* ANSI codepage 1252 */
	    kCFStringEncodingISOLatin1 = 0x0201, /* ISO 8859-1 */
	    kCFStringEncodingNextStepLatin = 0x0B01, /* NextStep encoding*/
	    kCFStringEncodingASCII = 0x0600, /* 0..127 (in creating CFString, values greater than 0x7F are treated as corresponding Unicode value) */
	    kCFStringEncodingUnicode = 0x0100, /* kTextEncodingUnicodeDefault  + kTextEncodingDefaultFormat (aka kUnicode16BitFormat) */
	    kCFStringEncodingUTF8 = 0x08000100, /* kTextEncodingUnicodeDefault + kUnicodeUTF8Format */
	    kCFStringEncodingNonLossyASCII = 0x0BFF, /* 7bit Unicode variants used by Cocoa & Java */

	    kCFStringEncodingUTF16 = 0x0100, /* kTextEncodingUnicodeDefault + kUnicodeUTF16Format (alias of kCFStringEncodingUnicode) */
	    kCFStringEncodingUTF16BE = 0x10000100, /* kTextEncodingUnicodeDefault + kUnicodeUTF16BEFormat */
	    kCFStringEncodingUTF16LE = 0x14000100, /* kTextEncodingUnicodeDefault + kUnicodeUTF16LEFormat */

	    kCFStringEncodingUTF32 = 0x0c000100, /* kTextEncodingUnicodeDefault + kUnicodeUTF32Format */
	    kCFStringEncodingUTF32BE = 0x18000100, /* kTextEncodingUnicodeDefault + kUnicodeUTF32BEFormat */
	    kCFStringEncodingUTF32LE = 0x1c000100 /* kTextEncodingUnicodeDefault + kUnicodeUTF32LEFormat */
	}

enum {
   OBJC_ASSOCIATION_ASSIGN = 0,
   OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1,
   OBJC_ASSOCIATION_COPY_NONATOMIC = 3,
   OBJC_ASSOCIATION_RETAIN = octal!1401,
   OBJC_ASSOCIATION_COPY = octal!1403
};

	void objc_msgSend(CFTypeRef obj, SEL sel, ...);
	void objc_msgSend_fpret(CFTypeRef obj, SEL sel, ...);
	void objc_msgSend_stret(CFTypeRef obj, SEL sel, ...);

	void objc_setAssociatedObject(CFTypeRef object, void *key, void* value, uint policy);
	void* objc_getAssociatedObject(CFTypeRef object, void *key);

	SEL sel_registerName(const char *str);
	const char* sel_getName(SEL aSelector);

	_ObjCClass objc_getClass(const char *name);
	_ObjCClass object_getClass(CFTypeRef object);
	void *object_getIndexedIvars(CFTypeRef obj);

	Method class_getInstanceMethod(_ObjCClass aClass, SEL aSelector);
	const char * class_getName(_ObjCClass cls);
	BOOL class_addMethod(_ObjCClass cls, SEL name, IMP imp, const char *types);
	BOOL class_addIvar(Class cls, const char *name, size_t size, uint8_t alignment, const char *types);
	Method * class_copyMethodList(Class cls, uint *outCount);

	CFTypeRef class_createInstance(Class cls, size_t extraBytes);

	SEL method_getName(Method method);
	const char * method_getTypeEncoding(Method method);

	_ObjCClass objc_allocateClassPair(_ObjCClass superclass, const char *name, size_t extraBytes);
	void objc_registerClassPair(_ObjCClass cls);
}

template MacFrameworkWithPath(string path)
{
	private static _load()
	{
		if (!_loaded)
		{
			debug writeln("Loading " ~ path);
			auto dl = dlopen(path.toStringz(), RTLD_LAZY);
			foreach(m; __traits(derivedMembers, typeof(this)))
			{
				mixin("alias _m = " ~ m ~ ";");
				static if (__traits(compiles, typeof(_m)))
				{
					static if (m != "_load" && std.traits.isPointer!(typeof(_m)))
					{
						static if (std.traits.isFunctionPointer!(_m))
						{
							static assert(std.traits.functionLinkage!(_m) == "C", m ~ " is not defined to be extern(C)");
							static if (m.startsWith("_"))
							{
								auto newM = m[1 .. $];
							}
							else
							{
								auto newM = m;
							}
							_m = cast(typeof(_m)) dlsym(dl, cast(const char*)newM);
							if (char* error = dlerror())
								writefln("dlsym error(%s): %s", newM, error);
						}
						else static if(__traits(getProtection, _m) == "public")
						{
							_m = *(cast(typeof(_m)*) dlsym(dl, m));
							if (char* error = dlerror())
								writefln("dlsym error(%s): %s", m, error);
						}
					}
				}
			}
			_loaded = true;
			_dl = cast(typeof(_dl))dl;
			bindUnboundClasses();
		}
	}

	shared private static this()
	{
		_load();
	}

	shared private static ~this()
	{
		dlclose(cast(void*)_dl);
	}

	shared private static bool _loaded = false;
	shared private static void* _dl;
}

template MacFrameworkWithName(string name)
{
	mixin MacFrameworkWithPath!("/System/Library/Frameworks/" ~ name ~ ".framework/" ~ name);
}

template MacFramework()
{
	mixin MacFrameworkWithName!(typeof(this).stringof);
}

extern (C) class CoreFoundation
{
	mixin MacFramework;

shared static:
	void function(CFTypeRef obj) CFShow;

	CFTypeRef function(CFTypeRef obj) CFRelease;
	CFTypeRef function(CFTypeRef obj) CFRetain;

	CFStringRef function(CFAllocatorRef alloc, const char* cStr, CFStringEncoding encoding) CFStringCreateWithCString;
	CFStringRef function(CFAllocatorRef alloc, CFArrayRef theArray, CFStringRef separatorString) CFStringCreateByCombiningStrings;
	CFStringRef function(CFAllocatorRef alloc, const UInt8 *bytes, CFIndex numBytes, CFStringEncoding encoding, Boolean isExternalRepresentation) CFStringCreateWithBytes;
	CFStringRef function(CFAllocatorRef alloc, const UInt8 *bytes, CFIndex numBytes, CFStringEncoding encoding, Boolean isExternalRepresentation, CFAllocatorRef contentsDeallocator) CFStringCreateWithBytesNoCopy;

	Boolean function (CFStringRef theString, char *buffer, CFIndex bufferSize, CFStringEncoding encoding) CFStringGetCString;

	CFIndex function(CFStringRef theString) CFStringGetLength;
	CFIndex function(CFIndex length, CFStringEncoding encoding) CFStringGetMaximumSizeForEncoding;

	CFAllocatorRef kCFAllocatorDefault;
	CFAllocatorRef kCFAllocatorNull;
}

extern (C) class Cocoa
{
	mixin MacFramework;

	version(X86_64)
		alias CGFloat = double;
	else
		alias CGFloat = float;

	align(1) struct CGPoint
	{
		CGFloat x = 0;
		CGFloat y = 0;
	}

	align(1) struct CGSize
	{
		CGFloat width = 0;
		CGFloat height = 0;
	}

	align(1) struct CGRect
	{
		this(CGPoint o, CGSize s)
		{
			origin = o;
			size = s;
		}

		this(CGFloat x, CGFloat y, CGFloat w, CGFloat h)
		{
			this(CGPoint(x, y), CGSize(w, h));
		}

		CGPoint origin;
		CGSize size;
	}

	alias NSPoint = CGPoint;
	alias NSSize = CGSize;
	alias NSRect = CGRect;

shared static:
	void function(CFTypeRef obj, ...) NSLog;

	private int function(int argc, const char** argv) NSApplicationMain;

	int applicationMain(string[] argv)
	{
		return NSApplicationMain(cast(int)argv.length, cast(const char**)argv);
	}
}

alias InitFunc = _ObjCClass function();

private InitFunc[string] _gUnboundClasses;
private InitFunc[string] _gUnregisteredClasses;

private bool handleHandlers(alias arr)()
{
	string[] success;
	foreach (k, v; arr)
		if (v()) success ~= k;

	if (success.length)
	{
		foreach (k; success)
			arr.remove(k);
		return true;
	}
	return false;
}

private void bindUnboundClasses()
{
	if (handleHandlers!_gUnboundClasses())
		registerUnregisteredClasses();
}

private void registerUnregisteredClasses()
{
	if (handleHandlers!_gUnregisteredClasses())
		registerUnregisteredClasses();
}

CFStringRef CFStringWithString(const char[] s)
{
	CFTypeRef result = CoreFoundation.CFStringCreateWithBytes(null, cast(const UInt8 *)s.ptr, s.length, CFStringEncoding.kCFStringEncodingUTF8, false);
	assert(result);
	return result;
}

string StringWithCFString(CFStringRef s)
{
	CFIndex len = CoreFoundation.CFStringGetLength(s);
	CFIndex maxSize = CoreFoundation.CFStringGetMaximumSizeForEncoding(len, CFStringEncoding.kCFStringEncodingUTF8);
	char[] array = new char[maxSize + 1];
	Boolean success = CoreFoundation.CFStringGetCString(s, array.ptr, array.length, CFStringEncoding.kCFStringEncodingUTF8);
	len = strlen(array.ptr);
	array = array[0 .. len];
	return assumeUnique(array);
}

auto DTypeToObjcType(T)(T a)
	if (isIntegral!T || isSomeChar!T || isPointer!T || isFloatingPoint!T || is(T == struct))
{
	return a;
}

auto DTypeToObjcType(string s)
{
	return CFStringWithString(s);
}

auto DTypeToObjcType(ObjCObj a)
{
	return a._base.mObj;
}

auto DTypeToObjcType(_ObjcBase a)
{
	return a._objcObject();
}

void* DTypeToObjcType(typeof(null) a)
{
	return null;
}

auto DTypeToObjcType(Variant a)
{
	writeln("Converting variant");
	const void* res = a.get!(ObjCObj)._base.mObj;
	writeln("Converting variant done");
	return res;
}

RetType ObjCTypeToDType(RetType, bool needsRetain)(void* a)
{
	return cast(RetType)a;
}

ObjCObj ObjCTypeToDType(RetType : ObjCObj, bool needsRetain)(void* a)
{
	return ObjCObj(a, needsRetain);
}

struct ObjCSelector(string name)
{
	static @property SEL selector()
	{
		if (_sel is null)
		{
			enum SelectorFromDFunc = name.replace("_", ":") ~ "\0";
			_sel = cast(shared SEL)sel_registerName(SelectorFromDFunc.ptr);
			assert(_sel);
		}
		return cast(SEL)_sel;
	}

	enum argCount = name.count('_');
	enum returnsAutoreleasedValue = !(name.startsWith("init") || name.startsWith("new") || name.startsWith("copy") || name.startsWith("mutableCopy"));

	shared static SEL _sel;
}

static assert(ObjCSelector!"selectorWithNothing".argCount == 0);
static assert(ObjCSelector!"selectorWithThis_".argCount == 1);
static assert(ObjCSelector!"selectorWithThis_andThat_".argCount == 2);

static assert(ObjCSelector!"length".returnsAutoreleasedValue);
static assert(!ObjCSelector!"init".returnsAutoreleasedValue);

extern(C) alias D_objc_msgSend_type(RetType, uint ArgCount, Args...) = RetType function(CFTypeRef obj, SEL sel, Args[0 .. ArgCount] args, ...);

RetType Dobjc_msgSend(RetType, uint ArgCount = Args.length, Args...)(CFTypeRef obj, SEL sel, Args args)
{
	return (cast(D_objc_msgSend_type!(RetType, ArgCount, Args))&objc_msgSend)(obj, sel, args);
}

RetType Dobjc_msgSend_fpret(RetType, uint ArgCount = Args.length, Args...)(CFTypeRef obj, SEL sel, Args args)
{
	return (cast(D_objc_msgSend_type!(RetType, ArgCount, Args))&objc_msgSend_fpret)(obj, sel, args);
}

RetType Dobjc_msgSend_stret(RetType, uint ArgCount = Args.length, Args...)(CFTypeRef obj, SEL sel, Args args)
{
	return (cast(D_objc_msgSend_type!(RetType, ArgCount, Args))&objc_msgSend_stret)(obj, sel, args);
}

struct ObjCBase(T)
{
	private static string expandConvertedArgs(string prefix, string suffix, string convertorFunc, int count)
	{
		string result = prefix;
		foreach (i; 0 .. count) result ~= "," ~ convertorFunc ~ "(args[" ~ to!string(i) ~ "])";
		result ~= suffix;
		return result;
	}

	RetType s(string name, RetType, Args...)(Args args)
	{
		enum selectorArgsCount = ObjCSelector!name.argCount;
		static assert(args.length == 0 || selectorArgsCount > 0, "Forgot to end your call with _?");

		enum selectorReturnsAutoreleasedValue = ObjCSelector!name.returnsAutoreleasedValue;

		static if (is (RetType == ObjCObj))
		{
			return ObjCObj(s!(name, CFTypeRef)(args), selectorReturnsAutoreleasedValue, name);
		}
		else static if (is (RetType : _ObjcBase))
		{
			CFTypeRef r = s!(name, CFTypeRef)(args);
			if (r is null) return null;

			alias RetTypeParent = BaseClassesTuple!RetType[0];

			static if (is(RetTypeParent == _ObjcBase))
			{
				// Native objc object
				RetType res = new RetType();
				static if (selectorReturnsAutoreleasedValue)
				{
					CoreFoundation.CFRetain(r);
				}
				res._obj.mObj = r;
				res._needsRelease = true;
				return res;
			}
			else
			{
				// Our objc object
				return cast(RetType)dObjectAssociatedWithObjCProxy(r);
			}
		}
		else static if (isIntegral!RetType || isSomeChar!RetType || isPointer!RetType || is(RetType == void))
		{
			mixin(expandConvertedArgs("return Dobjc_msgSend!(RetType, selectorArgsCount)(cast(CFTypeRef)mObj, ObjCSelector!(name).selector", ");", "DTypeToObjcType", args.length));
		}
		else static if (isFloatingPoint!RetType)
		{
			mixin(expandConvertedArgs("return Dobjc_msgSend_fpret!(RetType, selectorArgsCount)(cast(CFTypeRef)mObj, ObjCSelector!(name).selector", ");", "DTypeToObjcType", args.length));
		}
		else static if (is(RetType == struct))
		{
			mixin(expandConvertedArgs("return Dobjc_msgSend_stret!(RetType, selectorArgsCount)(cast(CFTypeRef)mObj, ObjCSelector!(name).selector", ");", "DTypeToObjcType", args.length));
		}
		else static if (is(RetType : string))
		{
			ObjCObj r = s!(name, ObjCObj)(args);
			return StringWithCFString(r._base.mObj);
		}
		else static if (false && is (RetType == Variant))
		{
			mixin(expandConvertedArgs("auto result = Dobjc_msgSend!(CFTypeRef, selectorArgsCount)(mObj, ObjCSelector!(name).selector", ");", "DTypeToObjcType", args.length));
			ObjCObj r = ObjCObj(result, selectorReturnsAutoreleasedValue, name);
			return Variant(r);
		}
	}

	T mObj;
}

struct ObjCObj
{
	ObjCBase!CFTypeRef _base;
//	alias _base this;

	string _sel;

	@disable this();

	this(CFTypeRef obj, bool needsRetain, string sel = null)
	{
		_sel = sel;
		_base.mObj = obj;
		if (needsRetain)
		{
			_retain();
//			writefln("Init retaining object %X, sel: %s", _base.mObj, _sel);
		}
		else
		{
//			writeln("Init assigning object %X, sel: %s", _base.mObj, _sel);
		}
	}

	this(this)
	{
//		writefln("Copying retaining object %X, sel: %s", _base.mObj, _sel);
//		Cocoa.NSLog(CFStringWithString("%@"), _base.mObj);
		_retain();
	}

	~this()
	{
//		writefln("Releasing object %X, sel: %s", _base.mObj, _sel);

	//	Cocoa.NSLog(CFStringWithString("s(%@)"), _base.mObj);
		_release();
	}

	ref ObjCObj opAssign(ObjCObj copy)
	{
		if (copy._base.mObj != _base.mObj)
		{
//			writefln("Assign copy retaining object old: %p, new: %p, sel: %s", _base.mObj, copy._base.mObj, _sel);

//			writefln("Assign copy retaining object old: ", _base.mObj, " new: ", copy._base.mObj, " sel: ", _sel);
			if (copy._base.mObj) copy._retain();
			if (_base.mObj) _release();
			_base.mObj = copy._base.mObj;
		}
		return this;
	}

	private void _retain()
	{
//		if (_base.mObj) CoreFoundation.CFRetain(_base.mObj);
	}

	private void _release()
	{
//		if (_base.mObj) CoreFoundation.CFRelease(_base.mObj);
	}

	RetType s(string name, RetType = ObjCObj, Args...)(Args args)
	{
		return _base.s!(name, RetType, Args)(args);
	}

	template opDispatch(string name)
	{
		RetType opDispatch(RetType = ObjCObj, Args...)(Args args)
		{
			return s!(name, ObjCObj, Args)(args);
		}
	}

	auto init_()
	{
		return s!("init", ObjCObj)();
	}
}

//templa

struct ObjC
{
	static alias opDispatch(string s) = _ObjcClass!s;
}

struct NSAutoreleasePool
{
	//@disable this() {}

	this(this)
	{
		assert(mAp is null);
	}

	~this()
	{
		if (mAp)
		{
			objc_msgSend(mAp, ObjCSelector!"drain".selector);
		}
	}

	@disable ref NSAutoreleasePool opAssign(NSAutoreleasePool copy);

	static NSAutoreleasePool opCall()
	{
		NSAutoreleasePool result;
		result.mAp = ObjC.NSAutoreleasePool.c.s!("new", CFTypeRef)();
		return result;
	}

	private CFTypeRef mAp;
}

unittest
{
	CFStringRef str = CFStringWithString("asdf");
	const(char)[] back = StringWithCFString(str);
	assert(back == "asdf");
	CoreFoundation.CFRelease(str);
}

unittest
{
	auto pool = NSAutoreleasePool();
	ObjCObj arr = ObjC.NSArray.c.s!("arrayWithObjects_", ObjCObj)("123", "456", "789", null);
	CFStringRef str = CoreFoundation.CFStringCreateByCombiningStrings(cast(CFTypeRef)CoreFoundation.kCFAllocatorDefault, arr._base.mObj, CFStringWithString(","));
	assert(StringWithCFString(str) == "123,456,789");
	CoreFoundation.CFRelease(str);
}

unittest
{
	auto pool = NSAutoreleasePool();
	ObjCObj s1 = ObjC.NSString.c.s!("alloc", ObjCObj)();
	s1 = s1.s!"init"();
	ObjCObj s2 = ObjC.NSString.c.s!("alloc", ObjCObj)().s!("initWithString_", ObjCObj)("hi");
	ObjCObj s3 = ObjC.NSString.c.s!("alloc", ObjCObj)().init_();
	ObjCObj arr = ObjC.NSArray.c.s!("alloc", ObjCObj)().initWithObjects_(s1, s2, s3, null);
	s1 = arr.componentsJoinedByString_(":");
	assert(StringWithCFString(s1._base.mObj) == ":hi:");
}

private bool containsOnlyTag(string str) pure
{
	str = str.strip();
	return str.startsWith("${") && str.endsWith("}") && str[2 .. $ - 1].isNumeric();
}

static assert(" ${123}   ".containsOnlyTag());
static assert(!" ${123} d ".containsOnlyTag());

private int[] tagsInString(string str) pure
{
	int[] res;
	int tag = str.tagInString();
	while (tag != -1)
	{
		str = str.replaceTagInString(tag, "");
		res ~= tag;
		tag = str.tagInString();
	}
	return res;
}

private int tagInString(string str) pure
{
	auto begin = str.indexOf("${");
	if (begin != -1)
	{
		auto end = begin + str[begin .. $].indexOf("}");
		return to!int(str[begin + 2 .. end]);
	}
	return -1;
}

static assert(tagInString("123 ${12} sdf") == 12);

private string replaceTagInString(string source, int tag, string replacement) pure
{
	return source.replace("${" ~ to!string(tag) ~ "}", replacement);
}

static assert("asd ${123} 456".replaceTagInString(123, "qwe") == "asd qwe 456");
static assert("asd ${123} ${456}".replaceTagInString(456, "qwe") == "asd ${123} qwe");

private class Expression
{
	this(string dCall, Expression[] exprs) pure
	{
		if (dCall.indexOf(":") != -1)
		{
			string[] parts = dCall.split(':');

			foreach(i, part; parts)
			{
				if (i == 0)
				{
					auto word = part.lastWordInString();
					_selector = word ~ "_";
					_target = part[0 .. $ - word.length];
				}
				else if (i == parts.length - 1)
				{
					_arguments ~= part;
				}
				else
				{
					auto word = part.lastWordInString();
					_selector ~= word ~ "_";
					_arguments ~= part[0 .. $ - word.length];
				}
			}
		}
		else
		{
			_selector = dCall.lastWordInString();
			_target = dCall[0 .. $ - _selector.length];
		}

		// Deduce type of arguments
		foreach (arg; _arguments)
		{
			foreach(tag; tagsInString(arg))
			{
				if (exprs[tag]._retType is null)
				{
					exprs[tag]._retType = "Variant";
				}
			}
		}

		// Deduce type of target
		if (_target.containsOnlyTag())
		{
			Expression targetExpr = exprs[_target.tagInString()];
			if (targetExpr._retType is null)
			{
				targetExpr._retType = "id";
			}
		}
		else
		{
			_target = "mixin(TargetFromString!`" ~ _target.strip() ~ "`)";
		}
	}

	string eval(Expression[] exprs) pure
	{
		assert(_retType.length);
		string result = "(" ~ _target ~ `).s!("` ~ _selector ~ `", ` ~ _retType ~")(";
		result ~= _arguments.join(",");
		result ~= ")";
		return result;
	}

	string _selector;
	string _target;
	string[] _arguments;
	string _retType;
}

private string lastWordInString(string s) pure
{
	return s.split!(a => !isAlphaNum(a))()[$ - 1];
}

private string evalLine(string line, Expression[] exprs) pure
{
	while(true)
	{
		auto begin = line.lastIndexOf("${");
		if (begin != -1)
		{
			auto end = begin + line[begin .. $].indexOf("}");
			auto index = to!uint(line[begin + 2 .. end]);
			line = line[0 .. begin] ~ exprs[index].eval(exprs) ~ line[end + 1 .. $];
		}
		else
		{
			break;
		}
	}
	return line;
}

private string assignmentTypeFromString(string s) pure
{
	if (s.length == 0)
	{
		return "void";
	}
	else
	{
		return `ReturnType!(
			delegate ()
			{
				static if (__traits(compiles, mixin("delegate void(){ struct _t { ` ~ s ~ `; }}()")))
				{
					mixin("struct _t { ` ~ s ~ `; }");
					return FieldTypeTuple!_t[0].init;
				}
				else
				{
					mixin("return(` ~ s ~ `);");
				}
			}
		)`;
	}
}

enum AssignmentType(string s) = assignmentTypeFromString(s);

private string targetFromString(string s) pure
{
	return `()
	{
		static if (__traits(compiles, mixin("(){ return (` ~ s ~ `); }()")))
		{
			mixin("return (` ~ s ~ `);");
		}
		else
		{
			mixin("return (` ~ s ~ `).c;");
		}
	}()`;
}

enum TargetFromString(string s) = targetFromString(s);

private string castTypeFromString(string s) pure
{
	string res = s.strip();
	if (res.length && res.endsWith(")"))
	{
		auto openingParen = s.lastIndexOf("(");
		res = s[openingParen .. $];
	}
	else
	{
		res = "";
	}
	return res;
}

static assert(castTypeFromString("asdf (int)") == "(int)");
static assert(castTypeFromString("asdf (int) 1234") == "");

string convertObjcToD(string objcCode) pure
{
	string result = "";
	foreach (line; objcCode.splitter(";")) if (line.length)
	{
		auto openingBracket = line.lastIndexOf("[");
		Expression[] exprs;
		while (openingBracket != -1)
		{
			auto closingBracket = line[openingBracket .. $].indexOf("]");
			if (closingBracket != -1)
			{
				closingBracket += openingBracket;
				auto castType = castTypeFromString(line[0 .. openingBracket]);
				auto expr = new Expression(line[openingBracket + 1 .. closingBracket], exprs);
				if (castType.length)
				{
					expr._retType = castType;
				}
				exprs ~= expr;
				line = line[0 .. openingBracket - castType.length] ~ "${" ~ to!string(exprs.length - 1) ~ "}" ~ line[closingBracket + 1 .. $];
				openingBracket = line.lastIndexOf("[");
			}
			else
			{
				break;
			}
		}

		if (exprs.length)
		{
			if (line.containsOnlyTag())
			{
				exprs[line.tagInString()]._retType = "void";
			}
			else
			{
				auto assignment = line.indexOf("=");
				if (assignment != -1)
				{
					exprs[line.tagInString()]._retType = "mixin(AssignmentType!`" ~ line[0 .. assignment].strip() ~ "`)";
				}
				else
				{
					assert(false, line);
				}
			}
			line = evalLine(line, exprs);
		}

		result ~= line.strip() == "" ? "" : line ~ ";";
	}

	return result;
}

template _ObjC(string s)
{
	enum _ObjC = convertObjcToD(s);
}

alias id = ObjCObj;

bool isChildOfClass(ClassInfo child, ClassInfo parent) @safe nothrow pure
{
	return child.base && (child.base is parent || child.base.isChildOfClass(parent));
}

private class _ObjcBase
{
	private ObjCBase!CFTypeRef _obj;

	private final CFTypeRef _objcObject()
	{
		if (_obj.mObj is null)
		{
			_obj.mObj = _createObjcObject();
		}
		return _obj.mObj;
	}

	protected final void _release()
	{
		if (_obj.mObj)
		{
			CoreFoundation.CFRelease(_obj.mObj);
			_obj.mObj = null;
		}
	}

	RetType s(string name, RetType = ObjCObj, Args...)(Args args)
	{
		return _obj.s!(name, RetType, Args)(args);
	}

	private ~this()
	{
		if (_needsRelease)
		{
			_release();
		}
	}

	protected abstract CFTypeRef _createObjcObject();
	private bool _needsRelease = false;
}

debug struct SelectorTypeCheck(string selectorName, string className, Args...)
{
    shared static this()
    {
		// TODO: perform type checks here
    }
}

class _ObjcClass(string className) : _ObjcBase
{
	template opDispatch(string name)
	{
		RetType opDispatch(RetType = ObjCObj, Args...)(Args args)
		{
			return s!(name, RetType, Args)(args);
		}
	}

    RetType s(string name, RetType = ObjCObj, Args...)(Args args)
    {
        debug alias Checker = SelectorTypeCheck!(name, className, Args);
        return super.s!(name, RetType, Args)(args);
    }

	static _ObjCClass objcClass()
	{
		return _objcClass.mObj is null ? bindObjcClass() : _objcClass.mObj;
	}

	private static _ObjCClass bindObjcClass()
	{
	//	writeln("Trying to bind class: ", className);

		_objcClass.mObj = objc_getClass(className.toStringz());
		if (_objcClass.mObj is null)
		{
			_gUnboundClasses[className] = &bindObjcClass;
		}
		else
		{
		//	writeln("Class bound: ", className);
		}
		return _objcClass.mObj;
	}

	protected override CFTypeRef _createObjcObject()
	{
		assert(false); // Objc object should be valid here
	}

	shared static this()
	{
		bindObjcClass();
	}

	~this()
	{
	//	_release();
	}

	__gshared static ObjCBase!_ObjCClass _objcClass;

	static @property auto c()
	{
		if (_objcClass.mObj is null)
		{
			bindObjcClass();
			assert(_objcClass.mObj, "Could not load class " ~ className);
		}
		return _objcClass;
	}
}

CFTypeRef allocObjCObjectAsProxyToD(_ObjCClass isa, _ObjcBase realObj)
{
	CFTypeRef result = class_createInstance(isa, realObj.sizeof);
	associateObjCProxyToDObject(result, realObj);
	return result;
}

private extern (C) CFTypeRef _allocImpl(T)(CFTypeRef o, SEL m, CFTypeRef zone)
{
	return allocObjCObjectAsProxyToD(T.c.mObj, new T());
}

void associateObjCProxyToDObject(CFTypeRef objcObj, _ObjcBase dObj)
{
	void** adjuscentBytes = cast(void**)object_getIndexedIvars(objcObj);
	assert(adjuscentBytes !is null);
	dObj._obj.mObj = objcObj;
	GC.addRoot(cast(void*)dObj);
	*adjuscentBytes = cast(void*)dObj;
}

private void* dObjectAssociatedWithObjCProxy(CFTypeRef objcObj)
{
	void** adjuscentBytes = cast(void**)object_getIndexedIvars(objcObj);
	assert(adjuscentBytes !is null);
	return *adjuscentBytes;
}

private extern (C) void _deallocImpl(T)(CFTypeRef o, SEL m)
{
	T impl = cast(T)dObjectAssociatedWithObjCProxy(o);
	impl._obj.mObj = null;
	GC.removeRoot(cast(void*)impl);
}

private extern (C) auto _methodForwarder(T, string Func, Args...)(CFTypeRef o, SEL m, Args args)
{
//	writeln("Forwarding call ", Func);
	T obj = cast(T)dObjectAssociatedWithObjCProxy(o);
//	writeln("Ok, calling now! ", cast(void*)obj);
	mixin("return obj." ~ Func ~ "(args);");
}

_ObjCClass _registerObjcClass(This, Super)()
{
	string thisName = This.stringof.split('.')[$ - 1];

	_ObjCClass superClass = Super.objcClass();
	if (superClass is null)
	{
		_gUnregisteredClasses[thisName] = &_registerObjcClass!(This, Super);
		return null;
	}

	_ObjCClass result = objc_allocateClassPair(superClass, thisName.toStringz(), This.sizeof);
	assert(result !is null);

	class_addMethod(object_getClass(result), ObjCSelector!"allocWithZone_".selector, cast(IMP)&(_allocImpl!This), "v@:".ptr);
	class_addMethod(result, ObjCSelector!"dealloc".selector, cast(IMP)&(_deallocImpl!This), "v@:".ptr);

	foreach(m; __traits(derivedMembers, This))
	{
		mixin("alias _m = This." ~ m ~ ";");
		static if (__traits(getProtection, _m) == "public")
		{
			static if (isCallable!(_m) && !__traits(isStaticFunction, _m) && m != "objcClass" && m != "__ctor" && m != "__dtor")
			{
				class_addMethod(result, ObjCSelector!m.selector, cast(IMP)&(_methodForwarder!(This, m, ParameterTypeTuple!_m)), "v@:".ptr);
			}
		}
	}

	objc_registerClassPair(result);
	//writeln("Class registered: ", This.stringof);
	return result;
}

mixin template RegisterObjCClass()
{
	private static _ObjCClass registerObjcClass()
	{
//		writeln("Trying to register class:", typeof(this).stringof);
		return _objcClass.mObj = _registerObjcClass!(typeof(this), typeof(super))();
	}

	static _ObjCClass objcClass()
	{
		return _objcClass.mObj is null ? registerObjcClass() : _objcClass.mObj;
	}

	private shared static this()
	{
		registerObjcClass();
	}

	protected override CFTypeRef _createObjcObject()
	{
		return allocObjCObjectAsProxyToD(_objcClass.mObj, this);
	}

	__gshared static ObjCBase!_ObjCClass _objcClass;
	alias c = _objcClass;
}

unittest
{
	ObjC.NSArray arr = ObjC.NSArray.c.s!("arrayWithObjects_", ObjC.NSArray)("Hello", "world!", null);
	ObjC.NSString str = arr.s!("componentsJoinedByString_", ObjC.NSString)(", ");
	uint length = str.s!("length", uint)();
	assert(length == "Hello, world!".length);
}

unittest
{
	mixin(_ObjC!q{
		ObjC.NSArray arr = [ObjC.NSArray arrayWithObjects: "Hello", "world!", null];
		ObjC.NSString str = [arr componentsJoinedByString: ", "];
		uint length = [str length];
		assert(length == "Hello, world!".length);
	});

	void TheFollowingCodeDoesNotNeedToRunJustEnsureItCompiles()
	{
		mixin(_ObjC!q{
		[[ObjC.NSColor redColor] set];
		});
	}
}

unittest
{
	mixin(_ObjC!q{
		id str = [ObjC.NSString stringWithString: "Hello, world!"];
		int length = [str length];
		assert(length == "Hello, world!".length);
	});

	immutable string duplicatedObjCCode =
	q{
		length = [str length];
		assert(length == "Hello, world!".length);
	};

	mixin(_ObjC!duplicatedObjCCode);
	mixin(_ObjC!duplicatedObjCCode);
	mixin(_ObjC!duplicatedObjCCode);
}

unittest
{
	mixin(_ObjC!q{
		float floatInput = 123.456;
		id num = [ObjC.NSNumber numberWithFloat: floatInput];
		float floatRes = [num floatValue];
		assert(floatRes > 123.455 && floatRes < 123.457, "Invalid floatRes: " ~ to!string(floatRes));

		// Test doubles
		num = [ObjC.NSNumber numberWithDouble: 456.789];
		double doubleRes = [num doubleValue];
		assert(doubleRes > 456.788 && doubleRes < 456.79, "Invalid doubleRes: " ~ to!string(doubleRes));

		// Test passing floats to objc methods with ellipsis
		string s = [ObjC.NSString stringWithFormat: "%d, %.3f, %d", 123, doubleRes, 456];
		assert(s == "123, 456.789, 456");
	});
}

unittest // Test passing and returning structs
{
	mixin(_ObjC!q{
		auto rect = Cocoa.NSRect(12, 34, 56, 78);
		id val = [ObjC.NSValue valueWithRect: rect];
		string res = [val description];
		assert(res == "NSRect: {{12, 34}, {56, 78}}");

		rect = Cocoa.NSRect.init;
		assert(rect == Cocoa.NSRect(0, 0, 0, 0));

		rect = [val rectValue];
		assert(rect == Cocoa.NSRect(12, 34, 56, 78));
	});
}

version(unittest) class Test : ObjC.NSObject
{
	mixin RegisterObjCClass;
}
