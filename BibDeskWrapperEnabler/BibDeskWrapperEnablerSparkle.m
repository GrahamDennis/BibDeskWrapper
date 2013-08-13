//
//  BibDeskWrapperEnablerSparkle.m
//  BibDeskWrapper
//
//  Created by Graham Dennis on 9/08/13.
//  Copyright (c) 2013 Graham Dennis. All rights reserved.
//

#import "BibDeskWrapperEnablerSparkle.h"
#import "BibDeskWrapperEnabler.h"
#import <objc/runtime.h>

@class SUUpdater;

@interface GRDInitializeSparkleNotAClass

+ (SUUpdater *)updaterForBundle:(NSBundle *)bundle;

- (void)resetUpdateCycle;
- (void)checkForUpdates:(id)sender;

- (NSString *)pathToRelaunchForUpdater:(SUUpdater *)updater;

@end

static NSString *pathToRelaunchForUpdater(id self, SEL _cmd, SUUpdater *updater)
{
    return [GRDBibDeskLauncherBundle() bundlePath];
}

void GRDInitializeSparkle()
{
    // Override some Sparkle behaviour
    Class updaterClass = NSClassFromString(@"SUUpdater");
    SUUpdater *updater = [updaterClass updaterForBundle:GRDBibDeskLauncherBundle()];
    
    // Find the first separator in the BibDesk menu...
    NSMenu *applicationSubmenu = [[[NSApp mainMenu] itemAtIndex:0] submenu];
    int i = 0;
    for (; i < [applicationSubmenu numberOfItems]; i++) {
        if ([[applicationSubmenu itemAtIndex:i] isSeparatorItem])
            break;
    }
    
    // ... and insert a menu item that can be used to manually trigger update checks.
    NSMenuItem *updateMenuItem = [[NSMenuItem alloc] initWithTitle:@"Check for BibDeskWrapper Updates…"
                                                            action:@selector(checkForUpdates:)
                                                     keyEquivalent:@""];
    [updateMenuItem setTarget:updater];
    [applicationSubmenu insertItem:updateMenuItem atIndex:i];
    [updateMenuItem release];
    
    // ... make sure when Sparkle would relaunch BibDesk it actually relaunches BibDeskWrapper.
    
    Class BDSKAppControllerClass = NSClassFromString(@"BDSKAppController");
    class_addMethod(BDSKAppControllerClass, @selector(pathToRelaunchForUpdater:), (IMP)pathToRelaunchForUpdater, "@@:@");
    
    [updater resetUpdateCycle];
}
