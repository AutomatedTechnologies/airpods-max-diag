// APDMainController.h — AirPods Max Diagnostics (Detroit Automation Academy)

#import <Cocoa/Cocoa.h>

@interface APDMainController : NSObject <NSWindowDelegate>

@property (nonatomic, strong) NSWindow *window;
- (void)showWindow;

@end
