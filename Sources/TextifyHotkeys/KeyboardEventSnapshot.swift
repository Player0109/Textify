import CoreGraphics

public struct KeyboardEventSnapshot: Equatable, Sendable {
    public enum EventType: Equatable, Sendable {
        case flagsChanged
        case keyDown
    }

    public let type: EventType
    public let keyCode: UInt16
    public let flags: UInt64
    public let timestampMs: Int
    public let isAutoRepeat: Bool

    public init(
        type: EventType,
        keyCode: UInt16,
        flags: UInt64,
        timestampMs: Int,
        isAutoRepeat: Bool
    ) {
        self.type = type
        self.keyCode = keyCode
        self.flags = flags
        self.timestampMs = timestampMs
        self.isAutoRepeat = isAutoRepeat
    }
}

public extension KeyboardEventSnapshot {
    init?(event: CGEvent, type: CGEventType) {
        let mappedType: EventType
        switch type {
        case .flagsChanged:
            mappedType = .flagsChanged
        case .keyDown:
            mappedType = .keyDown
        default:
            return nil
        }
        self.init(
            type: mappedType,
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags.rawValue,
            timestampMs: Int(event.timestamp / 1_000_000),
            isAutoRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        )
    }
}
