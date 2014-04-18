#!/usr/bin/env rdmd -debug -unittest -main

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
import core.vararg;

pragma(lib, "objc");

extern (C)
{
	alias SEL = const(void)*;
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

	void* objc_msgSend(CFTypeRef obj, SEL sel, ...);
	void* objc_msgSend_fpret(CFTypeRef obj, SEL sel, ...);
	void* objc_msgSend_stret(CFTypeRef obj, SEL sel, ...);

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

	shared static void function(CFTypeRef obj) CFShow;

	shared static CFTypeRef function(CFTypeRef obj) CFRelease;
	shared static CFTypeRef function(CFTypeRef obj) CFRetain;

	shared static CFStringRef function(CFAllocatorRef alloc, const char* cStr, CFStringEncoding encoding) CFStringCreateWithCString;
	shared static CFStringRef function(CFAllocatorRef alloc, CFArrayRef theArray, CFStringRef separatorString) CFStringCreateByCombiningStrings;
	shared static CFStringRef function(CFAllocatorRef alloc, const UInt8 *bytes, CFIndex numBytes, CFStringEncoding encoding, Boolean isExternalRepresentation) CFStringCreateWithBytes;
	shared static CFStringRef function(CFAllocatorRef alloc, const UInt8 *bytes, CFIndex numBytes, CFStringEncoding encoding, Boolean isExternalRepresentation, CFAllocatorRef contentsDeallocator) CFStringCreateWithBytesNoCopy;

	shared static Boolean function (CFStringRef theString, char *buffer, CFIndex bufferSize, CFStringEncoding encoding) CFStringGetCString;

	shared static CFIndex function(CFStringRef theString) CFStringGetLength;
	shared static CFIndex function(CFIndex length, CFStringEncoding encoding) CFStringGetMaximumSizeForEncoding;

	shared static CFAllocatorRef kCFAllocatorDefault;
	shared static CFAllocatorRef kCFAllocatorNull;
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
		CGFloat x;
		CGFloat y;
	}

	align(1) struct CGSize
	{
		CGFloat width;
		CGFloat height;
	}

	align(1) struct CGRect
	{
		CGPoint origin;
		CGSize size;
	}

	alias NSPoint = CGPoint;
	alias NSSize = CGSize;
	alias NSRect = CGRect;

	shared static void function(CFTypeRef obj, ...) NSLog;

	shared private static int function(int argc, const char** argv) NSApplicationMain;

	static int applicationMain(string[] argv)
	{
		return NSApplicationMain(cast(int)argv.length, cast(const char**)argv);
	}
}

alias InitFunc = _ObjCClass function();

private InitFunc[string] _gUnboundClasses;
private InitFunc[string] _gUnregisteredClasses;

private void bindUnboundClasses()
{
	string[] success;
	foreach (k, v; _gUnboundClasses)
	{
		if (v())
		{
			success ~= k;
		}
	}

	if (success.length)
	{
		foreach (k; success)
		{
			_gUnboundClasses.remove(k);
		}

		registerUnregisteredClasses();
	}
}

private void registerUnregisteredClasses()
{
	string[] success;

	foreach (k, v; _gUnregisteredClasses)
	{
		if (v())
		{
			success ~= k;
		}
	}

	if (success.length)
	{
		foreach (k; success)
		{
			_gUnregisteredClasses.remove(k);
		}
		registerUnregisteredClasses();
	}
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
	return to!string(array);
}

auto DTypeToObjcType(T)(T a)
	if (isIntegral!T || isSomeChar!T || isPointer!T)
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
			enum SelectorFromDFunc(string F) = F.replace("_", ":") ~ "\0";
			_sel = cast(shared SEL)sel_registerName(SelectorFromDFunc!(name).ptr);
		}
		assert(_sel);
		return cast(SEL)_sel;
	}

	shared static SEL _sel;
}

enum SelectorReturnsAutoreleasedValue(string name) = !(name.startsWith("init") || name.startsWith("new") || name.startsWith("copy") || name.startsWith("mutableCopy"));

static assert(SelectorReturnsAutoreleasedValue!"length");
static assert(!SelectorReturnsAutoreleasedValue!"init");

struct Dobjc_msgSend(RetType)
{
	static this()
	{
		f = cast(typeof(f))&objc_msgSend;
	}
	static extern (C) RetType function (CFTypeRef obj, SEL sel, ...) f;
}

struct ObjCBase(T)
{
	static string expandConvertedArgs(string prefix, string suffix, string convertorFunc, int count)
	{
		string result = prefix;
		foreach (i; 0 .. count) result ~= "," ~ convertorFunc ~ "(args[" ~ to!string(i) ~ "])";
		result ~= suffix;
		return result;
	}

	RetType s(string name, RetType, Args...)(Args args)
		if (is (RetType == ObjCObj))
	{
		RetType r = ObjCObj(s!(name, CFTypeRef, Args)(args), SelectorReturnsAutoreleasedValue!name, name);
		return r;
	}

	RetType s(string name, RetType, Args...)(Args args)
		if (is (RetType : _ObjcBase))
	{
		CFTypeRef r = s!(name, CFTypeRef, Args)(args);
		if (r is null) return null;

		alias RetTypeParent = BaseClassesTuple!RetType[0];

		static if (is(RetTypeParent == _ObjcBase))
		{
			// Native objc object
			RetType res = new RetType();
			static if (SelectorReturnsAutoreleasedValue!name)
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

	RetType s(string name, RetType, Args...)(Args args)
		if (isIntegral!RetType || isSomeChar!RetType || isPointer!RetType || is(RetType == void))
	{
		static assert(args.length == 0 || name.endsWith("_"), "Forgot to end your call with _?");
		mixin(expandConvertedArgs("return Dobjc_msgSend!(RetType).f(cast(CFTypeRef)mObj, ObjCSelector!(name).selector", ");", "DTypeToObjcType", args.length));
	}

	//RetType s(string name, RetType, Args...)(Args args)
	//	if (isFloatingPoint!RetType)
	//{
	//	static assert(args.length == 0 || name.endsWith("_"), "Forgot to end your call with _?");
	//	mixin(expandConvertedArgs("void* result = objc_msgSend(mObj, ObjCSelector!(name).selector", ");", "DTypeToObjcType", args.length));
	//	return ObjCTypeToDType!(RetType, SelectorReturnsAutoreleasedValue!name)(result);
	//}

static if (0)
{
	RetType s(string name, RetType, Args...)(Args args)
		if (is (RetType == Variant))
	{
		static assert(args.length == 0 || name.endsWith("_"), "Forgot to end your call with _?");
		mixin(expandConvertedArgs("void* result = objc_msgSend(mObj, ObjCSelector!(name).selector", ");", "DTypeToObjcType", args.length));
		ObjCObj r = ObjCObj(result, SelectorReturnsAutoreleasedValue!name, name);
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

	auto init()
	{
		return s!("init", ObjCObj)();
	}
}

class ObjC
{
	alias opDispatch(string s) = _ObjcClass!s;
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
	ObjCObj s3 = ObjC.NSString.c.s!("alloc", ObjCObj)().init();
	ObjCObj arr = ObjC.NSArray.c.s!("alloc", ObjCObj)().initWithObjects_(s1, s2, s3, null);
	s1 = arr.componentsJoinedByString_(":");
	assert(StringWithCFString(s1._base.mObj) == ":hi:");
}

bool containsOnlyTag(string str) pure
{
	str = str.strip();
	return str.startsWith("${") && str.endsWith("}") && str[2 .. $ - 1].isNumeric();
}

static assert(" ${123}   ".containsOnlyTag());
static assert(!" ${123} d ".containsOnlyTag());

int[] tagsInString(string str) pure
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

int tagInString(string str) pure
{
	long begin = str.indexOf("${");
	if (begin != -1)
	{
		long end = begin + str[begin .. $].indexOf("}");
		return to!int(str[begin + 2 .. end]);
	}
	return -1;
}

static assert(tagInString("123 ${12} sdf") == 12);

string replaceTagInString(string source, int tag, string replacement) pure
{
	return source.replace("${" ~ to!string(tag) ~ "}", replacement);
}

class Expression
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
					_target = "(" ~ part[0 .. $ - word.length] ~ ")";
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

string lastWordInString(string s) pure
{
	return s.split!(a => !isAlphaNum(a))()[$ - 1];
}

string evalLine(string line, Expression[] exprs) pure
{
	while(true)
	{
		long begin = line.lastIndexOf("${");
		if (begin != -1)
		{
			long end = begin + line[begin .. $].indexOf("}");
			int index = to!int(line[begin + 2 .. end]);
			line = line[0 .. begin] ~ exprs[index].eval(exprs) ~ line[end + 1 .. $];
		}
		else
		{
			break;
		}
	}
	return line;
}

string assignmentTypeFromString(string s) pure
{
	s = s.strip();
	if (s.indexOf(".") != -1) return "typeof(" ~ s ~ ")";

	if (s.length == 0) return "void";

	string word = s.lastWordInString();
	if (word.length == s.length)
	{
		return "typeof(" ~ word ~ ")";
	}

	return s[0 .. $ - word.length];
}

string[] assignmentTypesFromString(string s, uint uniqueCounter) pure
{
	string[] result;
	s = s.strip();
	if (s.length == 0)
	{
		result ~= "";
		result ~= "void";
	}
	else
	{
		string unique = to!string(uniqueCounter);
		string typeAlias = "TheType" ~ unique;
		result ~= `
			static if (__traits(compiles, (delegate void() { struct _test` ~ unique ~ ` { ` ~ s ~ `; }})()))
			{
				struct _test` ~ unique ~`
				{
					` ~ s ~ `;
				}

				alias ` ~ typeAlias ~ ` = FieldTypeTuple!_test` ~ unique ~ `[0];
			}
			else
			{
				mixin("alias ` ~ typeAlias ~ ` = typeof(` ~ s ~ `);");
			}`;
		result ~= typeAlias;
	}
	return result;
}


string castTypeFromString(string s) pure
{
	string res = s.strip();
	if (res.length && res[$ - 1] == ')')
	{
		long openingParen = s.lastIndexOf("(");
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
	uint uniqueCounter = 1;
	foreach (line; objcCode.splitter(";")) if (line.length)
	{
		long openingBracket = line.lastIndexOf("[");
		Expression[] exprs;
		while (openingBracket != -1)
		{
			long closingBracket = line[openingBracket .. $].indexOf("]");
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
				long assignment = line.indexOf("=");
				if (assignment != -1)
				{
					string[] assignmentTypes = assignmentTypesFromString(line[0 .. assignment], uniqueCounter);
					if (assignmentTypes[0].length)
					{
						line = assignmentTypes[0] ~ line;
					}
					assert(assignmentTypes[1].length);
					exprs[line.tagInString()]._retType = assignmentTypes[1];
				}
				else
				{
					assert(false, line);
				}
			}
			line = evalLine(line, exprs);
		}

		result ~= line ~ ";";
		++uniqueCounter;
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

class _ObjcBase
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

class _ObjcClass(string className) : _ObjcBase
{
	template opDispatch(string name)
	{
		RetType opDispatch(RetType = ObjCObj, Args...)(Args args)
		{
			return this.s!(name, RetType, Args)(args);
		}
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

// private extern (C) CFTypeRef _initImpl(T)(CFTypeRef o, SEL m, ...)
// {
// 	writeln("Constructing: ", class_getName(object_getClass(o)));
// 	associateObjCProxyToDObject(o, new T());
// 	return o;
// }


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
			static if (isCallable!(_m) && m != "objcClass")
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

version (unittest)
{
	extern (C) class TestFramework
	{
		mixin MacFrameworkWithPath!("/Users/yglukhov/Library/Developer/Xcode/DerivedData/testFramework-eehghotsfhwemhhgbwgqwttzqqsa/Build/Products/Debug/testFramework.framework/testFramework");

		shared static CFStringRef function(CFAllocatorRef alloc, const char *cStr, CFStringEncoding encoding) ZBStringCreateWithCString;
	}
}

unittest
{
	ObjC.testFramework fr = ObjC.testFramework.c.s!("alloc", ObjC.testFramework)().s!("init", ObjC.testFramework)();
}

unittest
{
	mixin(_ObjC!q{
		ObjC.NSArray arr = [ObjC.NSArray.c arrayWithObjects: "Hello", "world!", null];
		ObjC.NSString str = [arr componentsJoinedByString: ", "];
		uint length = [str length];
		assert(length == "Hello, world!".length);
	});

	void TheFollowingCodeDoesNotNeedToRunJustEnsureItCompiles()
	{
		mixin(_ObjC!q{
		[[ObjC.NSColor.c redColor] set];
		});
	}
}

version(unittest) class Test : ObjC.NSObject
{
	mixin RegisterObjCClass;
}


unittest
{
writeln("UNITTEST RUNNING!");
}
