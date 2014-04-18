#import "OView.h"

@implementation OView

- (void)drawRect:(NSRect)dirtyRect
{
	[[NSColor greenColor] set];
	NSRectFill(dirtyRect);
}

@end
