// APDMainController.m — AirPods Max Diagnostics (Detroit Automation Academy)
// Programmatic AppKit UI (no nib), macOS 10.13 floor.
// Buttons: Run Diagnostics · Restart AirPods Max… · Factory Reset… ·
//          Restart Services · Firmware Update… · Save Report
//          Force Restart Connection… · Force Firmware Update…  (apd-test-2)
//          Force USB Reset…  (apd-test-3: bus-level re-enumeration)
// First launch presents the SDS-8 welcome sheet (animated mark + the
// Academy startup sound from the library).

#import "APDMainController.h"
#import "APDDiagnostics.h"
#import <IOBluetooth/IOBluetooth.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOCFPlugIn.h>
#import <IOKit/usb/IOUSBLib.h>

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
// force firmware sheet + watch
@property (nonatomic, strong) NSWindow *forceSheet;
@property (nonatomic, strong) NSTextField *forceBody;
@property (nonatomic, strong) NSTimer *watchTimer;
@property (nonatomic) NSInteger watchTicks;
// welcome sheet
@property (nonatomic, strong) NSWindow *welcomeSheet;
@property (nonatomic, strong) NSTimer *pulseTimer;
@property (nonatomic, strong) NSImageView *welcomeIcon;
@property (nonatomic) BOOL pulseUp;
@end

@implementation APDMainController

// ------------------------------------------------------------- main menu
// apd-test-5 fix: apd-test-4 and earlier shipped with NO menu bar —
// main.m runs NSApplication without a nib (Info.plist carries no
// NSMainNibFile) and no code ever built a menu or called
// -[NSApplication setMainMenu:], so the running app showed no menus
// at all (owner report, 2026-11-10). The menu is constructed here,
// in code, like the rest of this app's UI: app menu (About, Quit),
// File (Save Report…, Close Window), Edit (standard first-responder
// editing — the report NSTextView is selectable), Diagnostics (the
// window's nine actions, same selectors as the buttons), Window,
// Help. Menu items targeting the controller mirror their button's
// enabled state via validateMenuItem:, so a probe run disables the
// menu path exactly as it disables the buttons.

- (NSMenuItem *)menuItemIn:(NSMenu *)menu title:(NSString *)title
                    action:(SEL)action key:(NSString *)key target:(id)target {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
        action:action keyEquivalent:(key ?: @"")];
    item.target = target;
    [menu addItem:item];
    return item;
}

- (void)installMainMenu {
    NSString *appName = @"AirPods Max Diagnostics";
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"Main Menu"];

    // App menu
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:appName];
    appItem.submenu = appMenu;
    [self menuItemIn:appMenu title:[@"About " stringByAppendingString:appName]
        action:@selector(orderFrontStandardAboutPanel:) key:nil target:nil];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [self menuItemIn:appMenu title:[@"Hide " stringByAppendingString:appName]
        action:@selector(hide:) key:@"h" target:nil];
    NSMenuItem *hideOthers = [self menuItemIn:appMenu title:@"Hide Others"
        action:@selector(hideOtherApplications:) key:@"h" target:nil];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [self menuItemIn:appMenu title:@"Show All"
        action:@selector(unhideAllApplications:) key:nil target:nil];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [self menuItemIn:appMenu title:[@"Quit " stringByAppendingString:appName]
        action:@selector(terminate:) key:@"q" target:nil];

    // File menu
    NSMenuItem *fileItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:fileItem];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    fileItem.submenu = fileMenu;
    [self menuItemIn:fileMenu title:@"Save Report…"
        action:@selector(saveReport:) key:@"s" target:self];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [self menuItemIn:fileMenu title:@"Close Window"
        action:@selector(performClose:) key:@"w" target:nil];

    // Edit menu — nil targets route through the first responder
    // (the report NSTextView: copy / select-all work; the text is
    // read-only, so cut/paste/delete validate off automatically).
    NSMenuItem *editItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:editItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    editItem.submenu = editMenu;
    [self menuItemIn:editMenu title:@"Undo" action:@selector(undo:) key:@"z" target:nil];
    NSMenuItem *redo = [self menuItemIn:editMenu title:@"Redo"
        action:@selector(redo:) key:@"Z" target:nil];
    redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [editMenu addItem:[NSMenuItem separatorItem]];
    [self menuItemIn:editMenu title:@"Cut" action:@selector(cut:) key:@"x" target:nil];
    [self menuItemIn:editMenu title:@"Copy" action:@selector(copy:) key:@"c" target:nil];
    [self menuItemIn:editMenu title:@"Paste" action:@selector(paste:) key:@"v" target:nil];
    [self menuItemIn:editMenu title:@"Delete" action:@selector(delete:) key:nil target:nil];
    [self menuItemIn:editMenu title:@"Select All" action:@selector(selectAll:) key:@"a" target:nil];

    // Diagnostics menu — the window's actions, same selectors.
    NSMenuItem *diagItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:diagItem];
    NSMenu *diagMenu = [[NSMenu alloc] initWithTitle:@"Diagnostics"];
    diagItem.submenu = diagMenu;
    [self menuItemIn:diagMenu title:@"Run Diagnostics"
        action:@selector(runDiagnostics:) key:@"r" target:self];
    [diagMenu addItem:[NSMenuItem separatorItem]];
    [self menuItemIn:diagMenu title:@"Restart AirPods Max…"
        action:@selector(showRestart:) key:nil target:self];
    [self menuItemIn:diagMenu title:@"Factory Reset…"
        action:@selector(showReset:) key:nil target:self];
    [diagMenu addItem:[NSMenuItem separatorItem]];
    [self menuItemIn:diagMenu title:@"Restart Services"
        action:@selector(restartServices:) key:nil target:self];
    [self menuItemIn:diagMenu title:@"Firmware Update…"
        action:@selector(showFirmware:) key:nil target:self];
    [diagMenu addItem:[NSMenuItem separatorItem]];
    [self menuItemIn:diagMenu title:@"Force Restart Connection…"
        action:@selector(forceRestartConnection:) key:nil target:self];
    [self menuItemIn:diagMenu title:@"Force Firmware Update…"
        action:@selector(showForceFirmware:) key:nil target:self];
    [self menuItemIn:diagMenu title:@"Force USB Reset…"
        action:@selector(forceUSBReset:) key:nil target:self];

    // Window menu
    NSMenuItem *windowItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:windowItem];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    windowItem.submenu = windowMenu;
    [self menuItemIn:windowMenu title:@"Minimize"
        action:@selector(performMiniaturize:) key:@"m" target:nil];
    [self menuItemIn:windowMenu title:@"Zoom"
        action:@selector(performZoom:) key:nil target:nil];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [self menuItemIn:windowMenu title:@"Bring All to Front"
        action:@selector(arrangeInFront:) key:nil target:nil];
    NSApp.windowsMenu = windowMenu;

    // Help menu
    NSMenuItem *helpItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:helpItem];
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
    helpItem.submenu = helpMenu;
    [self menuItemIn:helpMenu title:@"About Firmware Updates for AirPods (Apple Support)"
        action:@selector(openFirmwarePage:) key:nil target:self];
    NSApp.helpMenu = helpMenu;

    [NSApp setMainMenu:mainMenu];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.target == self) {
        for (NSButton *b in self.actionButtons) {
            if (b.action == item.action) return b.enabled;
        }
    }
    return YES;
}

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
    [self installMainMenu];
    self.diag = [[APDDiagnostics alloc] init];
    NSRect frame = NSMakeRect(0, 0, 880, 600);
    self.window = [[NSWindow alloc] initWithContentRect:frame
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                   NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"AirPods Max Diagnostics";
    self.window.minSize = NSMakeSize(880, 480);
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

    self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(16, 600 - 104, 848, 18)];
    self.statusLabel.stringValue =
        @"Not run yet — connect the AirPods Max by its Lightning cable and press Run Diagnostics.";
    self.statusLabel.font = [NSFont systemFontOfSize:12];
    self.statusLabel.bordered = NO; self.statusLabel.editable = NO;
    self.statusLabel.backgroundColor = [NSColor clearColor];
    self.statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [root addSubview:self.statusLabel];

    // Button bar — two rows; widths measured to their titles (apd-test-1
    // shipped Save Report at 64 px and clipped its title on the rig).
    CGFloat y = 600 - 140;
    NSButton *run = [self buttonWithTitle:@"Run Diagnostics" action:@selector(runDiagnostics:) x:16 width:132];
    NSButton *restart = [self buttonWithTitle:@"Restart AirPods Max…" action:@selector(showRestart:) x:156 width:168];
    NSButton *reset = [self buttonWithTitle:@"Factory Reset…" action:@selector(showReset:) x:332 width:122];
    NSButton *services = [self buttonWithTitle:@"Restart Services" action:@selector(restartServices:) x:462 width:132];
    NSButton *firmware = [self buttonWithTitle:@"Firmware Update…" action:@selector(showFirmware:) x:602 width:140];
    NSButton *save = [self buttonWithTitle:@"Save Report" action:@selector(saveReport:) x:750 width:114];
    save.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    NSButton *forceConn = [self buttonWithTitle:@"Force Restart Connection…" action:@selector(forceRestartConnection:) x:16 width:196];
    NSButton *forceFw = [self buttonWithTitle:@"Force Firmware Update…" action:@selector(showForceFirmware:) x:220 width:176];
    NSButton *forceUSB = [self buttonWithTitle:@"Force USB Reset…" action:@selector(forceUSBReset:) x:404 width:150];
    for (NSButton *b in @[run, restart, reset, services, firmware, save]) {
        CGRect f = b.frame; f.origin.y = y; b.frame = f;
        [root addSubview:b];
    }
    for (NSButton *b in @[forceConn, forceFw, forceUSB]) {
        CGRect f = b.frame; f.origin.y = y - 38; b.frame = f;
        [root addSubview:b];
    }
    run.keyEquivalent = @"\r";
    self.actionButtons = @[run, restart, reset, services, firmware, save, forceConn, forceFw, forceUSB];

    // Report view
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 16, 848, 600 - 212)];
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

// ------------------------------------------------------------- force actions

// Force Restart Connection: the strongest host-side reset that exists.
// Restarts the audio/Bluetooth daemons, then asks the Bluetooth stack to
// open a connection to the paired AirPods Max. (No macOS API can reboot
// the headphones themselves — Apple's design has none.)
- (void)forceRestartConnection:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Force restart the connection?";
    alert.informativeText = @"This restarts coreaudiod and bluetoothd (administrator "
        @"password required), then instructs the Bluetooth stack to connect to the "
        @"paired AirPods Max. Bluetooth devices disconnect briefly. Use it when the "
        @"headphones enumerate on USB but will not pair, connect, or route audio.";
    [alert addButtonWithTitle:@"Force Restart Connection"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSAlertFirstButtonReturn) return;
        NSDictionary *errInfo = nil;
        NSAppleScript *script = [[NSAppleScript alloc] initWithSource:
            @"do shell script \"killall coreaudiod; killall bluetoothd\" with administrator privileges"];
        [script executeAndReturnError:&errInfo];
        if (errInfo) {
            self.statusLabel.stringValue = @"Force restart did not complete — the services restart was refused or cancelled.";
            return;
        }
        self.statusLabel.stringValue = @"Services restarted — attempting to connect to the AirPods Max…";
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                IOBluetoothDevice *target = nil;
                for (IOBluetoothDevice *device in [IOBluetoothDevice pairedDevices]) {
                    if ([device.name containsString:@"AirPods Max"]) { target = device; break; }
                }
                if (!target) {
                    self.statusLabel.stringValue = @"Stack restarted, but this Mac has no pairing record for an AirPods Max — "
                        @"pair it in System Preferences > Bluetooth, then run Diagnostics.";
                    return;
                }
                IOReturn rc = [target openConnection];
                self.statusLabel.stringValue = (rc == kIOReturnSuccess)
                    ? @"Connection opened to the AirPods Max. Run Diagnostics to re-check audio and firmware."
                    : [NSString stringWithFormat:@"Stack restarted; the connect attempt returned 0x%x. "
                       @"If the headphones stay silent, their own buttons are the only reset path — see the Restart sheet's note.", rc];
            });
    }];
}

// Force Firmware Update: forces every host-side condition Apple requires,
// then watches the firmware version for up to 30 minutes. Apple delivers
// AirPods firmware automatically; no host command installs it directly.
- (void)showForceFirmware:(id)sender {
    NSWindow *sheet = [self makeSheetWithWidth:560 height:440];
    self.forceSheet = sheet;
    NSView *v = sheet.contentView;
    [v addSubview:[self labelAt:NSMakeRect(20, 440 - 44, 520, 22)
        text:@"Force Firmware Update — AirPods Max (Lightning)" size:14 bold:YES wrap:NO]];
    self.forceBody = [self labelAt:NSMakeRect(20, 440 - 356, 520, 300) text:@"Checking…" size:12 bold:NO wrap:YES];
    [v addSubview:self.forceBody];
    NSButton *start = [[NSButton alloc] initWithFrame:NSMakeRect(20, 20, 190, 30)];
    start.title = @"Start Force Sequence"; start.bezelStyle = NSBezelStyleRounded;
    start.target = self; start.action = @selector(startForceSequence:);
    [v addSubview:start];
    NSButton *close = [[NSButton alloc] initWithFrame:NSMakeRect(560 - 110, 20, 90, 30)];
    close.title = @"Close"; close.bezelStyle = NSBezelStyleRounded;
    close.target = self; close.action = @selector(closeForceFirmware:);
    [v addSubview:close];
    [self.window beginSheet:sheet completionHandler:nil];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self.diag runFirmwareProbes];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.forceBody.stringValue = [NSString stringWithFormat:
                @"Current firmware: %@\nLatest for this model: %@\n\n"
                @"Apple delivers AirPods firmware automatically — no Mac command installs\n"
                @"it directly, and no manual installer exists. The force sequence does\n"
                @"everything the host side allows:\n\n"
                @"1. Restarts coreaudiod and bluetoothd (administrator password).\n"
                @"2. Re-checks the delivery conditions (charging over USB, Bluetooth\n"
                @"   connected, this Mac on Wi-Fi).\n"
                @"3. Watches the firmware version every minute for 30 minutes and\n"
                @"   reports the moment it changes.\n\n"
                @"Keep the headphones on charge and in range while it watches.",
                self.diag.firmwareVersion ?: @"unknown (reads over Bluetooth)", kLatestFirmwareLightning];
        });
    });
}

- (void)startForceSequence:(id)sender {
    NSDictionary *errInfo = nil;
    NSAppleScript *script = [[NSAppleScript alloc] initWithSource:
        @"do shell script \"killall coreaudiod; killall bluetoothd\" with administrator privileges"];
    [script executeAndReturnError:&errInfo];
    if (errInfo) {
        self.forceBody.stringValue = @"The services restart was refused or cancelled — the force sequence cannot start.";
        return;
    }
    self.watchTicks = 0;
    [self.watchTimer invalidate];
    self.watchTimer = [NSTimer scheduledTimerWithTimeInterval:60 target:self
        selector:@selector(tickFirmwareWatch:) userInfo:nil repeats:YES];
    self.forceBody.stringValue = [NSString stringWithFormat:
        @"Force sequence running. Services restarted; conditions re-checked.\n"
        @"Watching the firmware version — check 0 of 30 (latest is %@).\n\n"
        @"Leave the headphones charging and in range.", kLatestFirmwareLightning];
}

- (void)tickFirmwareWatch:(NSTimer *)timer {
    self.watchTicks++;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self.diag runFirmwareProbes];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *current = self.diag.firmwareVersion;
            if ([current isEqualToString:kLatestFirmwareLightning]) {
                [self.watchTimer invalidate]; self.watchTimer = nil;
                self.forceBody.stringValue = [NSString stringWithFormat:
                    @"Firmware is now %@ — UP TO DATE. The update landed during the watch.", current];
                NSBeep();
            } else if (self.watchTicks >= 30) {
                [self.watchTimer invalidate]; self.watchTimer = nil;
                self.forceBody.stringValue =
                    @"No firmware change after 30 minutes of watching. Leave the headphones\n"
                    @"charging next to this Mac (or a paired iPhone) for a few hours — delivery\n"
                    @"is Apple's schedule, not the host's. If the version never moves and the\n"
                    @"headphones misbehave, an Apple Store / AASP visit is the remaining path.";
            } else {
                self.forceBody.stringValue = [NSString stringWithFormat:
                    @"Watching — check %ld of 30. Current firmware: %@ (latest %@).\n"
                    @"Keep the headphones charging and in range.",
                    (long)self.watchTicks, current ?: @"unknown", kLatestFirmwareLightning];
            }
        });
    });
}

- (void)closeForceFirmware:(id)sender {
    [self.watchTimer invalidate]; self.watchTimer = nil;
    if (self.forceSheet) [self.window endSheet:self.forceSheet];
    self.forceSheet = nil;
}

// Force USB Reset: a bus-level reset (re-enumeration) issued to the
// headphones over USB — the strongest command a host can send on the
// wire. Two cycles, then the probes re-run so the result is measured,
// not assumed. There is no deeper USB command in macOS, and Apple
// provides no USB firmware restore for AirPods on any host.
- (IOReturn)reenumerateAirPodsMax:(BOOL *)found {
    *found = NO;
    io_iterator_t iter;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault,
        IOServiceMatching("IOUSBDevice"), &iter);
    if (kr != KERN_SUCCESS) return kr;
    IOReturn result = kIOReturnNotFound;
    io_service_t svc;
    while ((svc = IOIteratorNext(iter))) {
        CFTypeRef v = IORegistryEntryCreateCFProperty(svc, CFSTR("idVendor"), kCFAllocatorDefault, 0);
        CFTypeRef p = IORegistryEntryCreateCFProperty(svc, CFSTR("idProduct"), kCFAllocatorDefault, 0);
        BOOL match = v && p && CFGetTypeID(v) == CFNumberGetTypeID()
            && [(__bridge NSNumber *)v intValue] == 0x05ac
            && [(__bridge NSNumber *)p intValue] == 0x1109;
        if (v) CFRelease(v);
        if (p) CFRelease(p);
        if (!match) { IOObjectRelease(svc); continue; }
        *found = YES;
        IOCFPlugInInterface **plugin = NULL;
        SInt32 score = 0;
        kr = IOCreatePlugInInterfaceForService(svc, kIOUSBDeviceUserClientTypeID,
            kIOCFPlugInInterfaceID, &plugin, &score);
        IOObjectRelease(svc);
        if (kr != KERN_SUCCESS || !plugin) { result = kr; break; }
        IOUSBDeviceInterface **dev = NULL;
        HRESULT hr = (*plugin)->QueryInterface(plugin,
            CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID *)&dev);
        (*plugin)->Release(plugin);
        if (hr != S_OK || !dev) { result = kIOReturnError; break; }
        kr = (*dev)->USBDeviceOpen(dev);
        if (kr == KERN_SUCCESS) {
            result = (*dev)->USBDeviceReEnumerate(dev, 0);
            (*dev)->USBDeviceClose(dev);
        } else {
            result = kr;
        }
        (*dev)->Release(dev);
        break;
    }
    IOObjectRelease(iter);
    return result;
}

- (void)forceUSBReset:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Force a USB bus reset of the AirPods Max?";
    alert.informativeText = @"This sends a bus-level reset (re-enumeration) to the "
        @"headphones over USB — the strongest reset a host can issue on the wire. "
        @"The device drops off the bus and re-enumerates; two cycles run, then "
        @"diagnostics re-check the bus so the result is measured. It cannot harm "
        @"the headphones. Note: no USB firmware restore exists for AirPods on any "
        @"host — this reset is the deepest USB action there is.";
    [alert addButtonWithTitle:@"Force USB Reset"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSAlertFirstButtonReturn) return;
        [self setButtonsEnabled:NO];
        self.statusLabel.stringValue = @"Forcing USB reset — cycle 1 of 2…";
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSMutableString *log = [NSMutableString stringWithString:@"\n[Force USB Reset]\n"];
            for (int cycle = 1; cycle <= 2; cycle++) {
                BOOL found = NO;
                IOReturn rc = [self reenumerateAirPodsMax:&found];
                if (!found) {
                    [log appendString:@"Cycle: device not found on the USB bus — connect the Lightning cable.\n"];
                    break;
                }
                [log appendFormat:@"Cycle %d: USBDeviceReEnumerate returned 0x%x (%@).\n",
                    cycle, rc, rc == KERN_SUCCESS ? @"reset accepted" : @"reset refused or failed"];
                if (cycle == 1) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.statusLabel.stringValue = @"Forcing USB reset — cycle 2 of 2…";
                    });
                    [NSThread sleepForTimeInterval:3.0];
                }
            }
            [self.diag runProbes];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.reportView.string = [(self.diag.reportText ?: @"") stringByAppendingString:log];
                self.statusLabel.stringValue = self.diag.usbFound
                    ? @"USB reset complete — the headphones re-enumerated on the bus. Re-check Bluetooth and audio in the report."
                    : @"USB reset complete — the headphones did NOT re-enumerate. The USB path itself is now in question (cable, port, device).";
                [self setButtonsEnabled:YES];
            });
        });
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
    NSWindow *sheet = [self makeSheetWithWidth:520 height:420];
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
    steps = [steps stringByAppendingString:
        @"\n\nIf the buttons do not respond at all: keep the headphones plugged\n"
        @"into USB power and repeat the hold once. Still nothing — the\n"
        @"headphones themselves are wedged, and no command from this Mac\n"
        @"can reboot them. Remaining paths: leave them OFF charge until the\n"
        @"battery fully drains (can take days), charge 30 minutes, and try\n"
        @"the hold again — or Apple service."];
    [v addSubview:[self labelAt:NSMakeRect(20, 420 - 44, 480, 22) text:title size:14 bold:YES wrap:NO]];
    [v addSubview:[self labelAt:NSMakeRect(20, 420 - 290, 480, 240) text:steps size:12 bold:NO wrap:YES]];
    self.guidedTimerLabel = [self labelAt:NSMakeRect(20, 420 - 340, 480, 30)
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
    [self.watchTimer invalidate];
}

@end
