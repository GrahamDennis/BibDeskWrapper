//
//  BibDeskWrapperEnabler.m
//  BibDeskWrapperEnabler
//
//  Created by Graham Dennis on 9/08/13.
//  Copyright (c) 2013 Graham Dennis. All rights reserved.
//
// Significant parts of this file are derived from WebKitLauncher/WebKitNightlyEnabler.m which is BSD-licensed

/*
 * Copyright (C) 2006, 2007, 2008, 2009 Apple Inc.  All rights reserved.
 * Copyright (C) 2006 Graham Dennis.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1.  Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 * 2.  Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 * 3.  Neither the name of Apple Inc. ("Apple") nor the names of
 *     its contributors may be used to endorse or promote products derived
 *     from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE AND ITS CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL APPLE OR ITS CONTRIBUTORS BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "BibDeskWrapperEnabler.h"
#import "BDSKLinkedFileDropboxEnabler.h"
#import "BibDeskWrapperEnablerSparkle.h"

static void enableWebKitNightlyBehaviour() __attribute__ ((constructor));

static NSString *WKNERunState = @"WKNERunState";
static NSString *WKNEShouldMonitorShutdowns = @"WKNEShouldMonitorShutdowns";

typedef enum {
    RunStateShutDown,
    RunStateInitializing,
    RunStateRunning
} WKNERunStates;

static char *bibdeskWrapperAppPath;

static int32_t systemVersion()
{
    static SInt32 version = 0;
    if (!version)
        Gestalt(gestaltSystemVersion, &version);
    
    return version;
}

static void myApplicationWillFinishLaunching(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetLocalCenter(), &myApplicationWillFinishLaunching, NULL, NULL);
    
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setInteger:RunStateRunning forKey:WKNERunState];
    [userDefaults synchronize];
    
    GRDInitializeLinkedFileDropboxPatch();
    GRDInitializeSparkle();
}

static void myApplicationWillTerminate(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setInteger:RunStateShutDown forKey:WKNERunState];
    [userDefaults synchronize];
}

NSBundle *GRDBibDeskLauncherBundle()
{
    NSString *executablePath = [NSString stringWithUTF8String:bibdeskWrapperAppPath];
    NSRange appLocation = [executablePath rangeOfString:@".app/" options:NSBackwardsSearch];
    NSString *appPath = [executablePath substringToIndex:appLocation.location + appLocation.length];
    return [NSBundle bundleWithPath:appPath];
}

extern char **_CFGetProcessPath() __attribute__((weak));
extern OSStatus _RegisterApplication(CFDictionaryRef additionalAppInfoRef, ProcessSerialNumber* myPSN) __attribute__((weak));

static void poseAsBibDeskWrapperApp()
{
    bibdeskWrapperAppPath = strdup(getenv("BibDeskWrapperAppPath"));
    if (!bibdeskWrapperAppPath)
        return;
    
    unsetenv("BibDeskWrapperAppPath");
    
    // Set up the main bundle early so it points at Safari.app
    CFBundleGetMainBundle();
    
    if (systemVersion() < 0x1060) {
        if (!_CFGetProcessPath)
            return;
        
        // Fiddle with CoreFoundation to have it pick up the executable path as being within WebKit.app
        char **processPath = _CFGetProcessPath();
        *processPath = NULL;
        setenv("CFProcessPath", bibdeskWrapperAppPath, 1);
        _CFGetProcessPath();
        unsetenv("CFProcessPath");
    } else {
        if (!_RegisterApplication)
            return;
        
        // Register the application with LaunchServices, passing a customized registration dictionary that
        // uses the WebKit launcher as the application bundle.
        NSBundle *bundle = GRDBibDeskLauncherBundle();
        NSMutableDictionary *checkInDictionary = [[bundle infoDictionary] mutableCopy];
        [checkInDictionary setObject:[bundle bundlePath] forKey:@"LSBundlePath"];
        [checkInDictionary setObject:[checkInDictionary objectForKey:(NSString *)kCFBundleNameKey] forKey:@"LSDisplayName"];
        _RegisterApplication((CFDictionaryRef)checkInDictionary, 0);
        [checkInDictionary release];
    }
}

static void enableWebKitNightlyBehaviour()
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    unsetenv("DYLD_INSERT_LIBRARIES");
    poseAsBibDeskWrapperApp();
    
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *defaultPrefs = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:RunStateShutDown], WKNERunState,
                                  [NSNumber numberWithBool:YES], WKNEShouldMonitorShutdowns, nil];
    [userDefaults registerDefaults:defaultPrefs];
    
    if ([userDefaults boolForKey:WKNEShouldMonitorShutdowns]) {
        WKNERunStates savedState = (WKNERunStates)[userDefaults integerForKey:WKNERunState];
        if (savedState == RunStateInitializing) {
            // Use CoreFoundation here as AppKit hasn't been initialized at this stage of Safari's lifetime
            CFOptionFlags responseFlags;
            CFUserNotificationDisplayAlert(0, kCFUserNotificationCautionAlertLevel,
                                           NULL, NULL, NULL,
                                           CFSTR("BibDeskWrapper failed to open correctly"),
                                           CFSTR("BibDeskWrapper failed to open correctly on your previous attempt. Please notify graham@grahamdennis.me of any problems."),
                                           CFSTR("Continue"), NULL, NULL, &responseFlags);
        }
        else if (savedState == RunStateRunning) {
            NSLog(@"BibDesk failed to shut down cleanly.");
        }
    }
    [userDefaults setInteger:RunStateInitializing forKey:WKNERunState];
    [userDefaults synchronize];
    
    CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), &myApplicationWillFinishLaunching,
                                    myApplicationWillFinishLaunching, (CFStringRef) NSApplicationWillFinishLaunchingNotification,
                                    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), &myApplicationWillTerminate,
                                    myApplicationWillTerminate, (CFStringRef) NSApplicationWillTerminateNotification,
                                    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    
    NSLog(@"BibDeskWrapper %@ initialized.", [GRDBibDeskLauncherBundle() objectForInfoDictionaryKey:@"CFBundleShortVersionString"]);
    
    [pool release];
}