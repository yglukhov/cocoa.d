#import "DTAppDelegate.h"

extern NSString* testFunc();

@interface AppDelegate : NSObject

- (void) doSomething;

@end

@interface DView : NSView

- (void) testMethod:(NSRect) rect andArg: (int) a;

@end

@implementation DTAppDelegate

- (void) testExternalDFunction
{
	AppDelegate* d = [[NSClassFromString(@"AppDelegate") alloc] init];
	[d doSomething];

	NSString* str = testFunc();
	NSAssert([str isEqualToString: @"Hello, World!"], @"Something wrong");
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	[self testExternalDFunction];
	// Insert code here to initialize your application

	[(DView*)self.dView testMethod: NSMakeRect(1.24, 5, 6, 7) andArg: 5];
}

@end
