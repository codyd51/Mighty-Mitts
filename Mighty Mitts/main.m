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
        // Necessary to create the shared application
        [NSApplication sharedApplication];
        // Manually spin up our app delegate
        AppDelegate* delegate = [[AppDelegate alloc] init];
        [NSApp setDelegate:delegate];
        [NSApp run];
    }
    return NSApplicationMain(argc, argv);
}
