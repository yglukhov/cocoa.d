//
//  DTAppDelegate.m
//  dtest2
//
//  Created by Yuriy Glukhov on 4/8/14.
//  Copyright (c) 2014 Zeo. All rights reserved.
//

#import "DTAppDelegate.h"

extern NSString* testFunc();

@interface AppDelegate : NSObject

- (void) doSomething;

@end

@implementation DTAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	AppDelegate* d = [[NSClassFromString(@"AppDelegate") alloc] init];
	[d doSomething];
	NSLog(@"%@", testFunc());
	// Insert code here to initialize your application
}

@end
