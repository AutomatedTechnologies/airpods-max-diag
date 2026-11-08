// APDDiagnostics.m — AirPods Max Diagnostics (Detroit Automation Academy)
// Mirrors the airpods-max-diag.sh probe set and verdict branches, using only
// stock macOS tools: /usr/sbin/system_profiler, /usr/sbin/ioreg,
// /usr/bin/pmset, /usr/bin/log, /usr/sbin/networksetup.

#import "APDDiagnostics.h"

static NSString *APDRunTask(NSString *path, NSArray<NSString *> *args) {
    NSTask *task = [[NSTask alloc] init];
    // Classic NSTask API: the 10.13 SDK headers do not declare
    // executableURL / runAndReturnError (verified by the SDK syntax gate).
    task.launchPath = path;
    task.arguments = args;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    @try { [task launch]; } @catch (NSException *e) { return @""; }
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

// The block of lines starting at the first line containing `marker`,
// plus the following `count` lines ("" when the marker is absent).
static NSString *APDBlockAfter(NSString *text, NSString *marker, NSUInteger count) {
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    for (NSUInteger i = 0; i < lines.count; i++) {
        if ([lines[i] containsString:marker]) {
            NSUInteger end = MIN(lines.count, i + count + 1);
            return [[lines subarrayWithRange:NSMakeRange(i, end - i)]
                componentsJoinedByString:@"\n"];
        }
    }
    return @"";
}

// Trimmed value after "Label:" on the first matching line of `text`.
static NSString *APDValueAfter(NSString *text, NSString *label) {
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSRange r = [line rangeOfString:label];
        if (r.location != NSNotFound) {
            NSString *rest = [line substringFromIndex:r.location + r.length];
            return [rest stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceCharacterSet]];
        }
    }
    return nil;
}

@interface APDDiagnostics ()
@property (nonatomic, readwrite) BOOL usbFound, audioFound, btPaired, btConnected;
@property (nonatomic, readwrite) BOOL btPowerOn, powerShort, dfuPresent, wifiOn;
@property (nonatomic, readwrite, copy) NSString *firmwareVersion;
@property (nonatomic, readwrite, copy) NSString *reportText;
@property (nonatomic, readwrite, copy) NSString *statusLine;
@property (nonatomic, copy) NSString *usbBlock, *ioBlock, *btBlock, *hostName;
@property (nonatomic, readwrite, copy) NSString *batterySummary;
@property (nonatomic, copy) NSString *batteryDetail;
@end

@implementation APDDiagnostics

- (void)probeUSBAndBT {
    NSString *usb = APDRunTask(@"/usr/sbin/system_profiler", @[@"SPUSBDataType"]);
    self.usbBlock = APDBlockAfter(usb, @"AirPods Max:", 18);
    self.usbFound = self.usbBlock.length > 0;

    NSString *io = APDRunTask(@"/usr/sbin/ioreg", @[@"-p", @"IOUSB", @"-w", @"0", @"-l"]);
    self.dfuPresent = [io containsString:@"\"idProduct\" = 4719"];
    // The AirPods Max node: locate idProduct 4361 (0x1109) and keep context.
    NSArray<NSString *> *ioLines = [io componentsSeparatedByString:@"\n"];
    NSMutableString *ctx = [NSMutableString string];
    for (NSUInteger i = 0; i < ioLines.count; i++) {
        if ([ioLines[i] containsString:@"\"idProduct\" = 4361"]) {
            NSUInteger from = (i > 4) ? i - 4 : 0;
            NSUInteger to = MIN(ioLines.count, i + 42);
            for (NSUInteger j = from; j < to; j++) [ctx appendFormat:@"%@\n", ioLines[j]];
            break;
        }
    }
    self.ioBlock = ctx;
    if (!self.usbFound && ctx.length > 0) self.usbFound = YES;

    // Battery query over USB: scan the device node's registry properties
    // for anything battery-shaped the unit will state on the wire.
    NSMutableArray<NSString *> *battLines = [NSMutableArray array];
    NSString *level = nil;
    for (NSString *line in [ctx componentsSeparatedByString:@"\n"]) {
        NSString *low = line.lowercaseString;
        if ([low containsString:@"battery"] || [low containsString:@"charge"] ||
            [low containsString:@"capacit"] || [low containsString:@"fuel"] ||
            [low containsString:@"cyclecount"] || [low containsString:@"cycle count"]) {
            NSString *t = [line stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceCharacterSet]];
            if (t.length) [battLines addObject:t];
            if (!level && ([low containsString:@"level"] || [low containsString:@"percent"] ||
                           [low containsString:@"charge"])) {
                NSRange eq = [t rangeOfString:@"="];
                if (eq.location != NSNotFound && t.length > eq.location + 1)
                    level = [[t substringFromIndex:eq.location + 1]
                        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            }
        }
    }
    self.batteryDetail = battLines.count ? [battLines componentsJoinedByString:@"\n"] : nil;
    self.batterySummary = level ?: (battLines.count ? @"reported (see report)" : nil);

    if (self.usbFound) {
        NSString *req = APDValueAfter(self.usbBlock, @"Current Required (mA):");
        NSString *avl = APDValueAfter(self.usbBlock, @"Current Available (mA):");
        if (req && avl && req.integerValue > avl.integerValue) self.powerShort = YES;
    }

    NSString *bt = APDRunTask(@"/usr/sbin/system_profiler", @[@"SPBluetoothDataType"]);
    self.btPowerOn = [APDValueAfter(bt, @"Bluetooth Power:") isEqualToString:@"On"];
    self.btBlock = APDBlockAfter(bt, @"AirPods Max", 10);
    self.btPaired = self.btBlock.length > 0;
    self.btConnected = self.btPaired &&
        ([self.btBlock rangeOfString:@"Connected: Yes"
            options:NSCaseInsensitiveSearch].location != NSNotFound);
    self.firmwareVersion = self.btPaired
        ? APDValueAfter(self.btBlock, @"Firmware Version:") : nil;
}

- (void)probeWiFi {
    NSString *ap = APDRunTask(@"/usr/sbin/networksetup", @[@"-getairportnetwork", @"en0"]);
    self.wifiOn = [ap containsString:@"Current Wi-Fi Network:"];
}

- (void)runFirmwareProbes {
    [self probeUSBAndBT];
    [self probeWiFi];
    self.statusLine = [self composeStatusLine];
}

- (void)runProbes {
    [self probeUSBAndBT];
    [self probeWiFi];

    NSString *audio = APDRunTask(@"/usr/sbin/system_profiler", @[@"SPAudioDataType"]);
    self.audioFound = [audio containsString:@"AirPods Max"];
    NSString *audioBlock = APDBlockAfter(audio, @"AirPods Max", 8);

    NSString *batt = APDRunTask(@"/usr/bin/pmset", @[@"-g", @"batt"]);
    NSString *logBT = APDRunTask(@"/usr/bin/log",
        @[@"show", @"--style", @"compact", @"--last", @"1h", @"--predicate",
          @"process == \"bluetoothd\" OR process == \"coreaudiod\""]);
    NSMutableArray<NSString *> *logLines = [NSMutableArray array];
    for (NSString *line in [logBT componentsSeparatedByString:@"\n"]) {
        NSString *low = line.lowercaseString;
        if ([low containsString:@"airpods"] || [low containsString:@"error"] ||
            [low containsString:@"fault"] || [low containsString:@"disconnect"]) {
            [logLines addObject:line];
            if (logLines.count > 40) [logLines removeObjectAtIndex:0];
        }
    }
    if (logLines.count > 15)
        logLines = [[logLines subarrayWithRange:
            NSMakeRange(logLines.count - 15, 15)] mutableCopy];

    self.hostName = APDRunTask(@"/usr/sbin/scutil", @[@"--get", @"ComputerName"]);
    self.hostName = [self.hostName stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    NSMutableString *r = [NSMutableString string];
    [r appendFormat:@"AIRPODS MAX (LIGHTNING) — USB DIAGNOSTIC\n"];
    [r appendFormat:@"host: %@ · %@\n", self.hostName ?: @"",
        [NSDateFormatter localizedStringFromDate:[NSDate date]
            dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterMediumStyle]];
    [r appendString:@"------------------------------------------------------------------------\n"];

    [r appendString:@"\n== 1 · USB ENUMERATION (system_profiler SPUSBDataType) ==\n"];
    if (self.usbFound && self.usbBlock.length) {
        [r appendFormat:@"%@\n", self.usbBlock];
        [r appendString:self.powerShort
            ? @">> POWER FAULT: device requires more current than the port offers.\n"
            : @">> USB layer ALIVE: device enumerated, power draw within the port's offer.\n"];
    } else if (self.usbFound) {
        [r appendString:@"Device node present in IORegistry (section 2); profiler block not captured.\n"];
    } else {
        [r appendString:@"AirPods Max NOT FOUND in the USB device tree.\n"];
    }

    [r appendString:@"\n== 2 · IOREG DEVICE NODE (descriptors, address, speed) ==\n"];
    if (self.ioBlock.length) {
        for (NSString *line in [self.ioBlock componentsSeparatedByString:@"\n"]) {
            for (NSString *key in @[@"\"USB Product Name\"", @"\"USB Serial Number\"",
                                    @"\"idVendor\"", @"\"idProduct\"", @"\"bcdDevice\"",
                                    @"\"locationID\"", @"\"USB Address\"", @"\"Device Speed\"",
                                    @"USBSuspend"]) {
                if ([line containsString:key]) { [r appendFormat:@"  %@\n", [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]]; break; }
            }
        }
        if ([self.ioBlock containsString:@"\"Device Speed\" = 1"])
            [r appendString:@">> Device Speed 1 = full speed (12 Mb/sec) — normal for this model's diagnostic interface.\n"];
    } else {
        [r appendString:@"No IOUSB device node with idProduct 4361 (0x1109).\n"];
    }
    if (self.dfuPresent)
        [r appendString:@">> NOTE: an Apple device in DFU mode (0x1227) is present on this bus.\n"];

    [r appendString:@"\n== 2b · BATTERY (queried over USB) ==\n"];
    if (self.batteryDetail.length) {
        [r appendFormat:@"%@\n", self.batteryDetail];
        [r appendString:@">> The device states battery data over USB (above).\n"];
    } else {
        [r appendString:@"The device reports NO battery level, charge state, or capacity over USB.\n"];
        [r appendString:@"   (AirPods expose battery only over a live Bluetooth link. On a unit that\n"];
        [r appendString:@"    never pairs, a USB battery query returns nothing by design — test the cell\n"];
        [r appendString:@"    by behaviour instead: charge for hours, then try the pairing hold while\n"];
        [r appendString:@"    still plugged in. Advertising on the wire but not off it = battery fault.)\n"];
    }

    [r appendString:@"\n== 3 · AUDIO LAYER (system_profiler SPAudioDataType) ==\n"];
    if (self.audioFound) {
        [r appendFormat:@"%@\n", audioBlock];
        [r appendString:@">> CoreAudio SEES the AirPods Max as an audio device.\n"];
    } else {
        [r appendString:@"AirPods Max does NOT appear as a CoreAudio device.\n"];
        [r appendString:@"   (Expected while connected by USB only — the Max is a Bluetooth audio\n"];
        [r appendString:@"    device; the Lightning lead carries power + diagnostics, not audio.)\n"];
    }

    [r appendString:@"\n== 4 · BLUETOOTH LAYER (system_profiler SPBluetoothDataType) ==\n"];
    [r appendFormat:@"  Bluetooth Power: %@\n", self.btPowerOn ? @"On" : @"Off/unknown"];
    if (self.btPaired) {
        [r appendFormat:@"%@\n", self.btBlock];
        if (self.firmwareVersion) [r appendFormat:@"  Firmware Version: %@\n", self.firmwareVersion];
        [r appendString:self.btConnected
            ? @">> Bluetooth link is UP.\n"
            : @">> Paired, but NOT currently connected over Bluetooth.\n"];
    } else {
        [r appendString:@"AirPods Max is not in the Bluetooth device list (never paired here, or pairing lost).\n"];
    }
    [r appendString:@"Host power:\n"];
    for (NSString *line in [batt componentsSeparatedByString:@"\n"])
        if (line.length) [r appendFormat:@"  %@\n", line];

    [r appendString:@"\n== 5 · RECENT LOG EVIDENCE (last 1h — bluetoothd, coreaudiod) ==\n"];
    if (logLines.count) [r appendFormat:@"%@\n", [logLines componentsJoinedByString:@"\n"]];
    else [r appendString:@"(no matching errors in the last hour)\n"];

    [r appendString:@"\n== VERDICT ==\n"];
    [r appendString:[self verdictText]];
    [r appendString:@"------------------------------------------------------------------------\nEND OF REPORT\n"];
    self.reportText = r;
    self.statusLine = [self composeStatusLine];
}

- (NSString *)composeStatusLine {
    return [NSString stringWithFormat:@"USB: %@ · Bluetooth: %@ · Audio: %@ · Firmware: %@ · Battery: %@",
        self.usbFound ? @"found" : @"not found",
        self.btConnected ? @"connected" : (self.btPaired ? @"paired, not connected" : @"not paired"),
        self.audioFound ? @"device present" : @"no device",
        self.firmwareVersion ?: @"unknown",
        self.batterySummary ?: @"not reported over USB"];
}

- (NSString *)verdictText {
    if (self.powerShort) {
        return @"USB POWER FAULT. Move the cable to a port on the Mac itself (no hub,\n"
               @"no keyboard pass-through), and try a second known-good Lightning cable.\n";
    }
    if (self.usbFound && !self.btConnected) {
        return @"USB layer is ALIVE (cable, port, headphone USB controller all proven)\n"
               @"but the headphones are not connected over Bluetooth — the classic\n"
               @"firmware-hang presentation for this model. Indicated recovery:\n"
               @"  1. Take the headphones OUT of the Smart Case (the case forces an\n"
               @"     ultra-low-power state that reads as non-responsive).\n"
               @"  2. Charge on this USB lead for 10 minutes, then RESTART the Max\n"
               @"     (button above): hold the noise-control button AND the Digital\n"
               @"     Crown together until the status light flashes amber.\n"
               @"  3. If still unresponsive, FACTORY RESET (button above): hold both\n"
               @"     buttons for 15 seconds, until the light flashes amber, then\n"
               @"     white. Then forget the device in Bluetooth preferences and pair\n"
               @"     again (hold the noise-control button until the light flashes\n"
               @"     white to enter pairing mode).\n"
               @"  4. If audio still does not route afterwards, use Restart Services\n"
               @"     to bounce coreaudiod/bluetoothd.\n";
    }
    if (self.usbFound && self.btConnected) {
        return @"USB enumerated AND Bluetooth connected. If sound is missing, check\n"
               @"System Preferences > Sound > Output names the AirPods Max, and the\n"
               @"headphones are out of the Smart Case. Section 5 log lines are the trail.\n";
    }
    return @"No USB enumeration at all — the fault is below the firmware layer:\n"
           @"  1. A deeply discharged Max can take minutes on charge before it\n"
           @"     enumerates. Leave it on a known-good Lightning cable with a\n"
           @"     5W-or-better USB source for 30 minutes, then rerun diagnostics.\n"
           @"  2. Swap the cable (charge-only and damaged data leads enumerate\n"
           @"     nothing), plug DIRECTLY into the Mac (no hub), try the other port.\n"
           @"  3. Inspect the Lightning port on the right earcup for lint/debris.\n"
           @"  4. If another Mac is available, plug in there: enumeration there\n"
           @"     clears this host; no enumeration anywhere + known-good cable\n"
           @"     points at the headphones' charge/USB board (hardware service).\n";
}

@end
