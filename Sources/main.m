// main.m — AirPods Max Diagnostics (Detroit Automation Academy)

#import <Cocoa/Cocoa.h>
#import "APDMainController.h"

@interface APDAppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) APDMainController *controller;
@end

@implementation APDAppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.controller = [[APDMainController alloc] init];
    [self.controller showWindow];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        APDAppDelegate *delegate = [[APDAppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
