import CoreGraphics
import Foundation

public enum CGEventTapMessage: Equatable, Sendable {
    case keyboardEvent(KeyboardEventSnapshot)
    case tapDisabledByTimeout
    case tapDisabledByUserInput
}

public struct CGEventTapHandle: @unchecked Sendable {
    fileprivate let port: CFMachPort?
    fileprivate let source: CFRunLoopSource?
    fileprivate let refcon: UnsafeMutableRawPointer?

    public init() {
        self.port = nil
        self.source = nil
        self.refcon = nil
    }

    fileprivate init(port: CFMachPort, source: CFRunLoopSource, refcon: UnsafeMutableRawPointer) {
        self.port = port
        self.source = source
        self.refcon = refcon
    }
}

public protocol CGEventTapClient: Sendable {
    func start(handler: @escaping @Sendable (CGEventTapMessage) -> Void) throws -> CGEventTapHandle
    func setEnabled(_ handle: CGEventTapHandle, enabled: Bool)
    func stop(_ handle: CGEventTapHandle)
}

public final class SystemCGEventTapClient: CGEventTapClient, @unchecked Sendable {
    public init() {}

    public func start(handler: @escaping @Sendable (CGEventTapMessage) -> Void) throws -> CGEventTapHandle {
        let mask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
        let box = EventHandlerBox(handler: handler)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let box = Unmanaged<EventHandlerBox>.fromOpaque(refcon).takeUnretainedValue()
                if type == .tapDisabledByTimeout {
                    box.handler(.tapDisabledByTimeout)
                    return Unmanaged.passUnretained(event)
                }
                if type == .tapDisabledByUserInput {
                    box.handler(.tapDisabledByUserInput)
                    return Unmanaged.passUnretained(event)
                }
                if let snapshot = KeyboardEventSnapshot(event: event, type: type) {
                    box.handler(.keyboardEvent(snapshot))
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            Unmanaged<EventHandlerBox>.fromOpaque(refcon).release()
            throw HotkeyMonitorError.eventTapCreationFailed
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            Unmanaged<EventHandlerBox>.fromOpaque(refcon).release()
            throw HotkeyMonitorError.runLoopSourceCreationFailed
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return CGEventTapHandle(port: port, source: source, refcon: refcon)
    }

    public func setEnabled(_ handle: CGEventTapHandle, enabled: Bool) {
        guard let port = handle.port else {
            return
        }
        CGEvent.tapEnable(tap: port, enable: enabled)
    }

    public func stop(_ handle: CGEventTapHandle) {
        guard let port = handle.port,
              let source = handle.source,
              let refcon = handle.refcon else {
            return
        }
        setEnabled(handle, enabled: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CFMachPortInvalidate(port)
        Unmanaged<EventHandlerBox>.fromOpaque(refcon).release()
    }
}

private final class EventHandlerBox: @unchecked Sendable {
    let handler: @Sendable (CGEventTapMessage) -> Void

    init(handler: @escaping @Sendable (CGEventTapMessage) -> Void) {
        self.handler = handler
    }
}
