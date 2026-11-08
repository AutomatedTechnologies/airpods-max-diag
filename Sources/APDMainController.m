// APDMainController.m — AirPods Max Diagnostics (Detroit Automation Academy)
// Programmatic AppKit UI (no nib), macOS 10.13 floor.
// Buttons: Run Diagnostics · Restart AirPods Max… · Factory Reset… ·
//          Restart Services · Firmware Update… · Save Report
// First launch presents the SDS-8 welcome sheet (animated mark + the
// Academy startup sound from the library).

#import "APDMainController.h"
#import "APDDiagnostics.h"

// Latest firmware for AirPods Max (Lightning), per Apple Support
// "About firmware updates for AirPods" (support.apple.com/en-us/106340),
// checked 2026-11-08.
static NSString * const kLatestFirmwareLightning = @"6F25";
static NSString * const kAppleFirmwarePage = @"https://support.apple.com/en-us/106340";

@interface APDMainController ()
@property (nonatomic, strong) APDDiagnostics *diag;
@property (nonatomic, strong) NSTextView *reportView;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSArray<NSButton *> *actionButtons;
// guided sheet
@property (nonatomic, strong) NSWindow *guidedSheet;
@property (nonatomic, strong) NSTextField *guidedTimerLabel;
@property (nonatomic, strong) NSTimer *guidedTimer;
@property (nonatomic) NSTimeInterval guidedDeadline;
@property (nonatomic) BOOL guidedIsReset;
// firmware sheet
@property (nonatomic, strong) NSWindow *firmwareSheet;
@property (nonatomic, strong) NSTextField *firmwareBody;
// welcome sheet
@property (nonatomic, strong) NSWindow *welcomeSheet;
@property (nonatomic, strong) NSTimer *pulseTimer;
@property (nonatomic, strong) NSImageView *welcomeIcon;
@property (nonatomic) BOOL pulseUp;
@end

@implementation APDMainController

- (NSButton *)buttonWithTitle:(NSString *)title action:(SEL)sel x:(CGFloat)x width:(CGFloat)w {
    NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(x, 0, w, 28)];
    b.title = title;
    b.bezelStyle = NSBezelStyleRounded;
    b.target = self;
    b.action = sel;
    b.autoresizingMask = NSViewMinYMargin;
    return b;
}

- (void)showWindow {
    self.diag = [[APDDiagnostics alloc] init];
    NSRect frame = NSMakeRect(0, 0, 800, 600);
    self.window = [[NSWindow alloc] initWithContentRect:frame
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                   NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"AirPods Max Diagnostics";
    self.window.minSize = NSMakeSize(680, 480);
    self.window.delegate = self;
    NSView *root = self.window.contentView;

    // Header: icon + title + status
    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect(16, 600 - 76, 56, 56)];
    icon.image = [NSApp applicationIconImage];
    icon.autoresizingMask = NSViewMinYMargin;
    [root addSubview:icon];

    NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(84, 600 - 52, 500, 24)];
    title.stringValue = @"AirPods Max Diagnostics";
    title.font = [NSFont boldSystemFontOfSize:16];
    title.bordered = NO; title.editable = NO; title.backgroundColor = [NSColor clearColor];
    title.autoresizingMask = NSViewMinYMargin;
    [root addSubview:title];

    NSTextField *sub = [[NSTextField alloc] initWithFrame:NSMakeRect(84, 600 - 72, 640, 16)];
    sub.stringValue = @"Detroit Automation Academy · for AirPods Max (Lightning generation)";
    sub.font = [NSFont systemFontOfSize:11];
    sub.textColor = [NSColor secondaryLabelColor];
    sub.bordered = NO; sub.editable = NO; sub.backgroundColor = [NSColor clearColor];
    sub.autoresizingMask = NSViewMinYMargin;
    [root addSubview:sub];

    self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(16, 600 - 104, 768, 18)];
    self.statusLabel.stringValue =
        @"Not run yet — connect the AirPods Max by its Lightning cable and press Run Diagnostics.";
    self.statusLabel.font = [NSFont systemFontOfSize:12];
    self.statusLabel.bordered = NO; self.statusLabel.editable = NO;
    self.statusLabel.backgroundColor = [NSColor clearColor];
    self.statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [root addSubview:self.statusLabel];

    // Button bar
    CGFloat y = 600 - 140;
    NSButton *run = [self buttonWithTitle:@"Run Diagnostics" action:@selector(runDiagnostics:) x:16 width:128];
    NSButton *restart = [self buttonWithTitle:@"Restart AirPods Max…" action:@selector(showRestart:) x:152 width:158];
    NSButton *reset = [self buttonWithTitle:@"Factory Reset…" action:@selector(showReset:) x:318 width:118];
    NSButton *services = [self buttonWithTitle:@"Restart Services" action:@selector(restartServices:) x:444 width:128];
    NSButton *firmware = [self buttonWithTitle:@"Firmware Update…" action:@selector(showFirmware:) x:580 width:132];
    NSButton *save = [self buttonWithTitle:@"Save Report" action:@selector(saveReport:) x:720 width:64];
    save.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    for (NSButton *b in @[run, restart, reset, services, firmware, save]) {
        CGRect f = b.frame; f.origin.y = y; b.frame = f;
        [root addSubview:b];
    }
    run.keyEquivalent = @"\r";
    self.actionButtons = @[run, restart, reset, services, firmware, save];

    // Report view
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 16, 768, 600 - 172)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.reportView = [[NSTextView alloc] initWithFrame:scroll.contentView.bounds];
    self.reportView.font = [NSFont fontWithName:@"Menlo" size:11] ?: [NSFont userFixedPitchFontOfSize:11];
    self.reportView.editable = NO;
    self.reportView.string = @"The diagnostic report appears here.\n\n"
        @"Probes: USB enumeration and power · IORegistry device node · CoreAudio\n"
        @"device list · Bluetooth pairing/link · recent bluetoothd/coreaudiod logs.\n";
    self.reportView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.documentView = self.reportView;
    [root addSubview:scroll];

    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [self presentWelcome];
}

// ---------------------------------------------------------------- actions

- (void)setButtonsEnabled:(BOOL)enabled {
    for (NSButton *b in self.actionButtons) b.enabled = enabled;
}

- (void)runDiagnostics:(id)sender {
    [self setButtonsEnabled:NO];
    self.statusLabel.stringValue = @"Running probes — system_profiler, ioreg, logs (a few seconds)…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self.diag runProbes];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.reportView.string = self.diag.reportText ?: @"";
            [self.reportView scrollToBeginningOfDocument:nil];
            self.statusLabel.stringValue = self.diag.statusLine;
            [self setButtonsEnabled:YES];
        });
    });
}

- (void)saveReport:(id)sender {
    if (!self.diag.reportText.length) {
        self.statusLabel.stringValue = @"Run Diagnostics first — there is no report to save yet.";
        return;
    }
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = @"airpods-max-diag.txt";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            NSError *error = nil;
            [self.diag.reportText writeToURL:panel.URL atomically:YES
                encoding:NSUTF8StringEncoding error:&error];
            self.statusLabel.stringValue = error
                ? [NSString stringWithFormat:@"Save failed: %@", error.localizedDescription]
                : [NSString stringWithFormat:@"Report saved to %@.", panel.URL.path];
        }
    }];
}

- (void)restartServices:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Restart audio and Bluetooth services?";
    alert.informativeText = @"This restarts coreaudiod and bluetoothd (administrator "
        @"password required). Bluetooth devices disconnect briefly and re-pair. "
        @"Use it when the AirPods Max is enumerated and connected but audio will not route.";
    [alert addButtonWithTitle:@"Restart Services"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSAlertFirstButtonReturn) return;
        NSDictionary *errInfo = nil;
        NSAppleScript *script = [[NSAppleScript alloc] initWithSource:
            @"do shell script \"killall coreaudiod; killall bluetoothd\" with administrator privileges"];
        [script executeAndReturnError:&errInfo];
        self.statusLabel.stringValue = errInfo
            ? @"Service restart did not complete — see the report notes."
            : @"Services restarted. Give Bluetooth ~15 seconds to re-pair, then Run Diagnostics again.";
        if (!errInfo && self.diag.reportText.length) {
            self.reportView.string = [self.diag.reportText stringByAppendingString:
                @"\n[Action] coreaudiod and bluetoothd restarted from the app.\n"];
        }
    }];
}

// ------------------------------------------------------- guided restart/reset

- (NSWindow *)makeSheetWithWidth:(CGFloat)w height:(CGFloat)h {
    NSWindow *sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, w, h)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    return sheet;
}

- (NSTextField *)labelAt:(NSRect)f text:(NSString *)text size:(CGFloat)size bold:(BOOL)bold wrap:(BOOL)wrap {
    NSTextField *t = [[NSTextField alloc] initWithFrame:f];
    t.stringValue = text;
    t.font = bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
    t.bordered = NO; t.editable = NO; t.backgroundColor = [NSColor clearColor];
    if (wrap) { t.lineBreakMode = NSLineBreakByWordWrapping; t.maximumNumberOfLines = 0; }
    return t;
}

- (void)showGuidedReset:(BOOL)isReset {
    self.guidedIsReset = isReset;
    [self.guidedTimer invalidate]; self.guidedTimer = nil;
    NSWindow *sheet = [self makeSheetWithWidth:520 height:340];
    NSView *v = sheet.contentView;
    NSString *title = isReset ? @"Factory Reset — AirPods Max" : @"Restart — AirPods Max";
    NSString *steps = isReset
        ? @"1. Take the headphones out of the Smart Case and put them on charge.\n"
          @"2. Press Start, then hold BOTH the noise-control button and the\n"
          @"    Digital Crown, together, for the full 15-second countdown.\n"
          @"3. The status light flashes amber, then white. Release.\n"
          @"4. On this Mac: System Preferences > Bluetooth > remove the\n"
          @"    AirPods Max, then hold the noise-control button until the light\n"
          @"    flashes white and pair again."
        : @"1. Take the headphones out of the Smart Case.\n"
          @"2. Hold BOTH the noise-control button and the Digital Crown,\n"
          @"    together, until the status light flashes amber.\n"
          @"3. Release both buttons. The headphones restart.\n"
          @"4. Wait ~30 seconds, then Run Diagnostics to re-check the link.";
    [v addSubview:[self labelAt:NSMakeRect(20, 340 - 44, 480, 22) text:title size:14 bold:YES wrap:NO]];
    [v addSubview:[self labelAt:NSMakeRect(20, 340 - 190, 480, 140) text:steps size:12 bold:NO wrap:YES]];
    self.guidedTimerLabel = [self labelAt:NSMakeRect(20, 340 - 240, 480, 30)
        text:(isReset ? @"Press Start when you are holding both buttons." : @"No timer needed — hold until the light flashes amber.")
        size:13 bold:YES wrap:NO];
    [v addSubview:self.guidedTimerLabel];

    if (isReset) {
        NSButton *start = [[NSButton alloc] initWithFrame:NSMakeRect(20, 20, 130, 30)];
        start.title = @"Start 15 s Hold"; start.bezelStyle = NSBezelStyleRounded;
        start.target = self; start.action = @selector(startGuidedTimer:);
        [v addSubview:start];
    }
    NSButton *done = [[NSButton alloc] initWithFrame:NSMakeRect(520 - 110, 20, 90, 30)];
    done.title = @"Done"; done.bezelStyle = NSBezelStyleRounded;
    done.target = self; done.action = @selector(closeGuided:);
    [v addSubview:done];
    self.guidedSheet = sheet;
    [self.window beginSheet:sheet completionHandler:nil];
}

- (void)showRestart:(id)sender { [self showGuidedReset:NO]; }
- (void)showReset:(id)sender { [self showGuidedReset:YES]; }

- (void)startGuidedTimer:(id)sender {
    self.guidedDeadline = [NSDate timeIntervalSinceReferenceDate] + 15.0;
    [self.guidedTimer invalidate];
    self.guidedTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self
        selector:@selector(tickGuidedTimer:) userInfo:nil repeats:YES];
}

- (void)tickGuidedTimer:(NSTimer *)timer {
    NSTimeInterval left = self.guidedDeadline - [NSDate timeIntervalSinceReferenceDate];
    if (left <= 0) {
        [self.guidedTimer invalidate]; self.guidedTimer = nil;
        self.guidedTimerLabel.stringValue = @"Release now — the light should flash amber, then white.";
        NSBeep();
    } else {
        self.guidedTimerLabel.stringValue =
            [NSString stringWithFormat:@"Keep holding both buttons… %.1f s", left];
    }
}

- (void)closeGuided:(id)sender {
    [self.guidedTimer invalidate]; self.guidedTimer = nil;
    if (self.guidedSheet) [self.window endSheet:self.guidedSheet];
    self.guidedSheet = nil;
}

// ---------------------------------------------------------------- firmware

- (void)showFirmware:(id)sender {
    NSWindow *sheet = [self makeSheetWithWidth:560 height:400];
    self.firmwareSheet = sheet;
    NSView *v = sheet.contentView;
    [v addSubview:[self labelAt:NSMakeRect(20, 400 - 44, 520, 22)
        text:@"Firmware Update — AirPods Max (Lightning)" size:14 bold:YES wrap:NO]];
    self.firmwareBody = [self labelAt:NSMakeRect(20, 400 - 330, 520, 270) text:@"Checking…" size:12 bold:NO wrap:YES];
    [v addSubview:self.firmwareBody];

    NSButton *page = [[NSButton alloc] initWithFrame:NSMakeRect(20, 20, 210, 30)];
    page.title = @"Open Apple's Firmware Page"; page.bezelStyle = NSBezelStyleRounded;
    page.target = self; page.action = @selector(openFirmwarePage:);
    [v addSubview:page];
    NSButton *recheck = [[NSButton alloc] initWithFrame:NSMakeRect(240, 20, 90, 30)];
    recheck.title = @"Recheck"; recheck.bezelStyle = NSBezelStyleRounded;
    recheck.target = self; recheck.action = @selector(recheckFirmware:);
    [v addSubview:recheck];
    NSButton *close = [[NSButton alloc] initWithFrame:NSMakeRect(560 - 110, 20, 90, 30)];
    close.title = @"Close"; close.bezelStyle = NSBezelStyleRounded;
    close.target = self; close.action = @selector(closeFirmware:);
    [v addSubview:close];

    [self.window beginSheet:sheet completionHandler:nil];
    [self refreshFirmwareBody];
}

- (void)refreshFirmwareBody {
    self.firmwareBody.stringValue = @"Checking…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self.diag runFirmwareProbes];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *current = self.diag.firmwareVersion;
            NSString *state;
            if (!current) state = @"Unknown — the version reads over Bluetooth; connect the headphones first.";
            else if ([current isEqualToString:kLatestFirmwareLightning]) state = @"UP TO DATE.";
            else state = @"An update applies (delivered automatically — see conditions).";
            NSString *(^mark)(BOOL) = ^NSString *(BOOL ok) { return ok ? @"✓" : @"✗"; };
            self.firmwareBody.stringValue = [NSString stringWithFormat:
                @"Current firmware: %@\n"
                @"Latest for AirPods Max (Lightning): %@  (Apple Support, checked 2026-11-08)\n"
                @"Status: %@\n\n"
                @"Apple delivers AirPods firmware automatically — there is no manual\n"
                @"installer. The update installs when ALL of these are true:\n\n"
                @"  %@  Charging (USB lead connected — this probe: %@)\n"
                @"  %@  Connected over Bluetooth to this Mac\n"
                @"  %@  This Mac connected to Wi-Fi\n\n"
                @"Leave the headphones charging and in range for about 30 minutes.\n"
                @"If no paired Apple device is available, Apple's documented fallback\n"
                @"is an Apple Store / Authorized Service Provider appointment.",
                current ?: @"—", kLatestFirmwareLightning, state,
                mark(self.diag.usbFound), self.diag.usbFound ? @"enumerated" : @"not found",
                mark(self.diag.btConnected),
                mark(self.diag.wifiOn)];
        });
    });
}

- (void)recheckFirmware:(id)sender { [self refreshFirmwareBody]; }
- (void)openFirmwarePage:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kAppleFirmwarePage]];
}
- (void)closeFirmware:(id)sender {
    if (self.firmwareSheet) [self.window endSheet:self.firmwareSheet];
    self.firmwareSheet = nil;
}

// ---------------------------------------------------------------- welcome (SDS-8 form)

- (void)presentWelcome {
    NSWindow *sheet = [self makeSheetWithWidth:440 height:340];
    self.welcomeSheet = sheet;
    NSView *v = sheet.contentView;

    self.welcomeIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(440/2 - 56, 340 - 150, 112, 112)];
    self.welcomeIcon.image = [NSApp applicationIconImage];
    [v addSubview:self.welcomeIcon];
    NSTextField *wtitle = [self labelAt:NSMakeRect(20, 340 - 190, 400, 24)
        text:@"AirPods Max Diagnostics" size:16 bold:YES wrap:NO];
    wtitle.alignment = NSTextAlignmentCenter;
    [v addSubview:wtitle];
    NSTextField *by = [self labelAt:NSMakeRect(20, 340 - 216, 400, 18)
        text:@"Detroit Automation Academy" size:12 bold:NO wrap:NO];
    by.alignment = NSTextAlignmentCenter;
    [v addSubview:by];
    NSTextField *body = [self labelAt:NSMakeRect(30, 340 - 290, 380, 56)
        text:@"Diagnose a USB-connected AirPods Max (Lightning) that will not respond: "
             @"USB, Bluetooth, audio and firmware — with guided restart and reset."
        size:12 bold:NO wrap:YES];
    body.alignment = NSTextAlignmentCenter;
    [v addSubview:body];

    NSButton *go = [[NSButton alloc] initWithFrame:NSMakeRect(440/2 - 60, 18, 120, 32)];
    go.title = @"Continue"; go.bezelStyle = NSBezelStyleRounded;
    go.target = self; go.action = @selector(closeWelcome:);
    [v addSubview:go];

    // Startup sound from the Academy library (bundled byte-identical).
    NSString *soundPath = [[NSBundle mainBundle] pathForResource:@"startup-sound" ofType:@"wav"];
    if (soundPath) {
        NSSound *sound = [[NSSound alloc] initWithContentsOfFile:soundPath byReference:YES];
        [sound play];
    }
    // Gentle pulse on the mark while the sheet is up.
    self.pulseUp = NO;
    self.pulseTimer = [NSTimer scheduledTimerWithTimeInterval:0.9 target:self
        selector:@selector(tickPulse:) userInfo:nil repeats:YES];
    [self.window beginSheet:sheet completionHandler:nil];
}

- (void)tickPulse:(NSTimer *)timer {
    self.pulseUp = !self.pulseUp;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.85;
        self.welcomeIcon.animator.alphaValue = self.pulseUp ? 0.72 : 1.0;
    } completionHandler:nil];
}

- (void)closeWelcome:(id)sender {
    [self.pulseTimer invalidate]; self.pulseTimer = nil;
    if (self.welcomeSheet) [self.window endSheet:self.welcomeSheet];
    self.welcomeSheet = nil;
}

- (void)windowWillClose:(NSNotification *)notification {
    [self.pulseTimer invalidate];
    [self.guidedTimer invalidate];
}

@end
