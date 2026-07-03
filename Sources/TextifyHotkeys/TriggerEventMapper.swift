public struct TriggerEventMapper: Sendable {
    private let trigger: TriggerPreference
    private var rightCommandDown = false

    public init(trigger: TriggerPreference = .rightCommand) {
        self.trigger = trigger
    }

    public mutating func map(_ event: KeyboardEventSnapshot) -> TriggerEvent? {
        guard trigger == .rightCommand else {
            return nil
        }
        if event.type == .keyDown, event.keyCode == TriggerKeyMatcher.escapeKeyCode {
            return .escapeKeyDown(timestampMs: event.timestampMs)
        }
        if event.type == .keyDown, rightCommandDown {
            return .nonTriggerKeyDown(timestampMs: event.timestampMs, isModifierOnly: false)
        }
        guard event.type == .flagsChanged else {
            return nil
        }
        if event.keyCode == TriggerKeyMatcher.leftCommandKeyCode {
            return nil
        }
        if event.keyCode == TriggerKeyMatcher.rightCommandKeyCode {
            let commandPresent = (event.flags & TriggerKeyMatcher.commandFlagMask) != 0
            if !rightCommandDown {
                guard commandPresent else {
                    return nil
                }
                rightCommandDown = true
                return .triggerDown(timestampMs: event.timestampMs)
            }
            rightCommandDown = false
            return .triggerUp(timestampMs: event.timestampMs)
        }
        if rightCommandDown {
            return .nonTriggerKeyDown(timestampMs: event.timestampMs, isModifierOnly: true)
        }
        return nil
    }
}
