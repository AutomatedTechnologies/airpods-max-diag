// APDDiagnostics.h — AirPods Max Diagnostics (Detroit Automation Academy)
// Probe engine: USB / IORegistry / CoreAudio / Bluetooth / power / logs for a
// USB-connected, non-responsive AirPods Max (Lightning generation:
// VID 0x05ac, PID 0x1109). UI-independent; safe to call off the main thread.

#import <Foundation/Foundation.h>

@interface APDDiagnostics : NSObject

@property (nonatomic, readonly) BOOL usbFound;
@property (nonatomic, readonly) BOOL audioFound;
@property (nonatomic, readonly) BOOL btPaired;
@property (nonatomic, readonly) BOOL btConnected;
@property (nonatomic, readonly) BOOL btPowerOn;
@property (nonatomic, readonly) BOOL powerShort;
@property (nonatomic, readonly) BOOL dfuPresent;
@property (nonatomic, readonly) BOOL wifiOn;

@property (nonatomic, readonly, copy) NSString *firmwareVersion; // nil when not readable
@property (nonatomic, readonly, copy) NSString *reportText;
@property (nonatomic, readonly, copy) NSString *statusLine;

// Full probe pass (system_profiler x3, ioreg, pmset, log). Synchronous —
// call from a background queue.
- (void)runProbes;

// Light pass for the Firmware panel: USB presence, Bluetooth state,
// Wi-Fi state, firmware version. No log queries.
- (void)runFirmwareProbes;

@end
