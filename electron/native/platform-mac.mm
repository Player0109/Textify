#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <iostream>
#include <string>
#include <thread>
#include <chrono>

static pid_t target() { return NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier; }
static std::string identity() {
    NSRunningApplication *app = NSWorkspace.sharedWorkspace.frontmostApplication;
    return std::to_string(app.processIdentifier) + ":" + std::to_string((long long)(app.launchDate.timeIntervalSince1970 * 1000));
}
static NSString *applicationIcon(NSImage *image) {
    if (!image) return @"";
    // A 48 px in-memory PNG provides a sharp 24 pt Retina icon without exposing
    // app bundle paths to the renderer or retaining a disk cache.
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:nullptr pixelsWide:48 pixelsHigh:48
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    if (!context) return @"";
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = context;
    context.imageInterpolation = NSImageInterpolationHigh;
    [image drawInRect:NSMakeRect(0, 0, 48, 48) fromRect:NSZeroRect
           operation:NSCompositingOperationCopy fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (!png || png.length > 10000) return @"";
    return [@"data:image/png;base64," stringByAppendingString:[png base64EncodedStringWithOptions:0]];
}
static bool secure(pid_t pid) {
    AXUIElementRef app = AXUIElementCreateApplication(pid);
    CFTypeRef field = nullptr, subrole = nullptr;
    bool result = false;
    if (AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute, &field) == kAXErrorSuccess && field) {
        if (AXUIElementCopyAttributeValue((AXUIElementRef)field, kAXSubroleAttribute, &subrole) == kAXErrorSuccess && subrole)
            result = CFEqual(subrole, kAXSecureTextFieldSubrole);
    }
    if (subrole) CFRelease(subrole);
    if (field) CFRelease(field);
    CFRelease(app);
    return result;
}
int main(int argc, char **argv) {
    @autoreleasepool {
        auto json = [](id object) { NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nullptr]; if (!data) return 2; std::cout.write((const char *)data.bytes, data.length); std::cout << "\n"; return 0; };
        if (argc == 2 && std::string(argv[1]) == "apps") {
            NSMutableArray *apps = [NSMutableArray array];
            NSMutableSet *seen = [NSMutableSet set];
            for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications) {
                if (!app.bundleIdentifier || !app.localizedName || app.activationPolicy != NSApplicationActivationPolicyRegular || [seen containsObject:app.bundleIdentifier]) continue;
                [seen addObject:app.bundleIdentifier]; [apps addObject:@{@"id":app.bundleIdentifier, @"name":app.localizedName}];
            }
            return json(apps);
        }
        if (argc == 2 && std::string(argv[1]) == "target") {
            const auto pid = target();
            NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
            NSString *targetID = [NSString stringWithFormat:@"%d:%lld", pid, (long long)(app.launchDate.timeIntervalSince1970 * 1000)];
            return json(@{@"target": targetID, @"secure": @(secure(pid)), @"appID":app.bundleIdentifier ?: @"", @"appName":app.localizedName ?: @"", @"appIcon":applicationIcon(app.icon)});
        }
        if (argc != 3 || std::string(argv[1]) != "paste") return 2;
        std::string input((std::istreambuf_iterator<char>(std::cin)), {});
        if (input.empty() || input.size() > 65536) return 2;
        pid_t pid = atoi(argv[2]);
        auto matches = [&] { return pid > 0 && identity() == argv[2] && !secure(pid); };
        if (!matches()) { std::cout << "{\"status\":\"skipped\"}\n"; return 0; }
        if (!AXIsProcessTrusted()) { std::cout << "{\"status\":\"unavailable\"}\n"; return 0; }
        NSPasteboard *board = NSPasteboard.generalPasteboard;
        const auto originalCount = board.changeCount;
        NSMutableArray<NSPasteboardItem *> *snapshot = [NSMutableArray array];
        NSUInteger totalBytes = 0;
        for (NSPasteboardItem *item in board.pasteboardItems) {
            NSPasteboardItem *copy = [[NSPasteboardItem alloc] init];
            for (NSPasteboardType type in item.types) {
                NSData *data = [item dataForType:type];
                if (!data || (totalBytes += data.length) > 64 * 1024 * 1024) { std::cout << "{\"status\":\"unavailable\"}\n"; return 0; }
                [copy setData:data forType:type];
            }
            [snapshot addObject:copy];
        }
        CGEventRef down = CGEventCreateKeyboardEvent(nullptr, 9, true);
        CGEventRef up = CGEventCreateKeyboardEvent(nullptr, 9, false);
        if (!down || !up) {
            if (down) CFRelease(down);
            if (up) CFRelease(up);
            std::cout << "{\"status\":\"unavailable\"}\n"; return 0;
        }
        if (board.changeCount != originalCount || !matches()) {
            CFRelease(down); CFRelease(up);
            std::cout << "{\"status\":\"skipped\"}\n"; return 0;
        }
        NSString *text = [[NSString alloc] initWithBytes:input.data() length:input.size() encoding:NSUTF8StringEncoding];
        if (!text) { CFRelease(down); CFRelease(up); return 2; }
        NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
        [item setString:text forType:NSPasteboardTypeString];
        [item setData:[NSData data] forType:@"org.nspasteboard.TransientType"];
        [item setData:[NSData data] forType:@"org.nspasteboard.ConcealedType"];
        [board clearContents];
        const bool written = [board writeObjects:@[item]];
        const auto writeCount = board.changeCount;
        bool sent = false;
        if (written && matches()) {
            CGEventSetFlags(down, kCGEventFlagMaskCommand);
            CGEventSetFlags(up, kCGEventFlagMaskCommand);
            CGEventPost(kCGHIDEventTap, down);
            CGEventPost(kCGHIDEventTap, up);
            sent = true;
            std::this_thread::sleep_for(std::chrono::milliseconds(200));
        }
        if (board.changeCount == writeCount) {
            [board clearContents];
            if (snapshot.count) [board writeObjects:snapshot];
        }
        CFRelease(down); CFRelease(up);
        std::cout << "{\"status\":\"" << (sent ? "sent" : "skipped") << "\"}\n";
    }
}
