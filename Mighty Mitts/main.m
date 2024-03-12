//
//  main.m
//  Mighty Mitts
//
//  Created by Phillip Tennen on 10/03/2024.
//

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Manually spin up and attach our app delegate
        [[NSApplication sharedApplication] setDelegate:[[AppDelegate alloc] init]];
        // And kick off the event loop
        [NSApp run];
    }
    return NSApplicationMain(argc, argv);
}
