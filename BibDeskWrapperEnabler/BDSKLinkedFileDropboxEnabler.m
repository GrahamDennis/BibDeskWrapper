//
//  BDSKLinkedFileDropboxEnabler.m
//  BibDeskWrapper
//
//  Created by Graham Dennis on 9/08/13.
//  Copyright (c) 2013 Graham Dennis. All rights reserved.
//

#import "BDSKLinkedFileDropboxEnabler.h"

#import <Cocoa/Cocoa.h>
#import <objc/objc-runtime.h>
#import "BibDeskWrapperEnabler.h"

@class BDSKLinkedFile;

@interface NotAnObject

- (const FSRef *)fileRef;
- (void)updateFileRef;
- (void)setFileRef:(const FSRef *)newFileRef;
- (void)linkedFileURLChanged:(BDSKLinkedFile *)file;

@end

static id (*BDSKLinkedAliasFileURLOriginalImplementation)(id self, SEL _cmd);

static void setFileRef(id self, FSRef *const fsRef)
{
    if ([self respondsToSelector:@selector(setFileRef:)])
        [self setFileRef:fsRef];
    else {
        object_setInstanceVariable(self, "fileRef", fsRef);
    }
}

static const FSRef *updateAndGetFileRef(id self)
{
    const FSRef *result = NULL;
    if ([self respondsToSelector:@selector(fileRef)]) {
        result = [self fileRef];
    } else if ([self respondsToSelector:@selector(updateFileRef)]) {
        [self updateFileRef];
        object_getInstanceVariable(self, "fileRef", (void **)&result);
    }
    return result;
}

// Replacement implementation for -[BDSKLinkedFile URL]
static id BDSKLinkedAliasFileURLPatch(id self, SEL _cmd)
{
    const FSRef *fileRef = NULL;
    NSURL *lastURL = nil;
    ptrdiff_t isInitial = NO;
    id delegate = nil;
    if (!object_getInstanceVariable(self, "fileRef", (void **)&fileRef) ||
        !object_getInstanceVariable(self, "lastURL", (void **)&lastURL) ||
        !object_getInstanceVariable(self, "isInitial", (void **)&isInitial) ||
        !object_getInstanceVariable(self, "delegate", (void **)&delegate) ||
        !([self respondsToSelector:@selector(fileRef)] ||
          [self respondsToSelector:@selector(updateFileRef)])) {
            // Fall through to original implementation
            return BDSKLinkedAliasFileURLOriginalImplementation(self, _cmd);
        }
    
    BOOL hadFileRef = fileRef != NULL;
    if (!hadFileRef) {
        fileRef = updateAndGetFileRef(self);
    }
    CFURLRef aURL = fileRef ? CFURLCreateFromFSRef(NULL, fileRef) : NULL;
    
    BOOL moved = [(NSURL *)aURL isEqual:lastURL] == NO && (aURL != NULL && lastURL != nil);
    if ((aURL == NULL || moved) && hadFileRef) {
        // fileRef was invalid, or URL moved, try to update it
        setFileRef(self, NULL);
        fileRef = updateAndGetFileRef(self);

        if (fileRef != NULL) {
            if (aURL) CFRelease(aURL);
            aURL = CFURLCreateFromFSRef(NULL, fileRef);
        }
    }
    BOOL changed = ([(NSURL *)aURL isEqual:lastURL] == NO && (aURL != NULL || lastURL != nil)) || moved;
    if (changed) {
        [lastURL release];
        lastURL = [(NSURL *)aURL retain];
        NSParameterAssert(lastURL);
        object_setInstanceVariable(self, "lastURL", (void*)lastURL);
        if (isInitial == NO && [delegate respondsToSelector:@selector(linkedFileURLChanged:)]) {
            [delegate performSelector:@selector(linkedFileURLChanged:) withObject:self afterDelay:0.0];
        }
    }
    isInitial = NO;
    object_setInstanceVariable(self, "isInitial", (void*)isInitial);
    
    return [(NSURL *)aURL autorelease];
}

void GRDInitializeLinkedFileDropboxPatch()
{
    // Override some Sparkle behaviour
    Method methodToPatch = class_getInstanceMethod(objc_getRequiredClass("BDSKLinkedAliasFile"), @selector(URL));
    BDSKLinkedAliasFileURLOriginalImplementation = (id (*)(id,SEL))method_getImplementation(methodToPatch);
    method_setImplementation(methodToPatch, (IMP)BDSKLinkedAliasFileURLPatch);
}
