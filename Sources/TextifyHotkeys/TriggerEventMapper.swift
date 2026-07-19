public struct TriggerEventMapper: Sendable {
    private let trigger: TriggerPreference
    private var triggerIsDown = false

    public init(trigger: TriggerPreference = .rightCommand) {
        self.trigger = trigger
    }

    public mutating func map(_ event: KeyboardEventSnapshot) -> TriggerEvent? {
        if event.type == .keyDown, event.keyCode == TriggerKeyMatcher.escapeKeyCode {
            return .escapeKeyDown(timestampMs: event.timestampMs)
        }

        switch trigger {
        case .rightCommand:
            return mapModifier(
                event,
                rightKeyCode: TriggerKeyMatcher.rightCommandKeyCode,
                leftKeyCode: TriggerKeyMatcher.leftCommandKeyCode,
                flagMask: TriggerKeyMatcher.commandFlagMask
            )
        case .rightOption:
            return mapModifier(
                event,
                rightKeyCode: TriggerKeyMatcher.rightOptionKeyCode,
                leftKeyCode: TriggerKeyMatcher.leftOptionKeyCode,
                flagMask: TriggerKeyMatcher.optionFlagMask
            )
        case .rightControl:
            return mapModifier(
                event,
                rightKeyCode: TriggerKeyMatcher.rightControlKeyCode,
                leftKeyCode: TriggerKeyMatcher.leftControlKeyCode,
                flagMask: TriggerKeyMatcher.controlFlagMask
            )
        case .controlSpace:
            return mapControlSpace(event)
        }
    }

    private mutating func mapModifier(
        _ event: KeyboardEventSnapshot,
        rightKeyCode: UInt16,
        leftKeyCode: UInt16,
        flagMask: UInt64
    ) -> TriggerEvent? {
        if event.type == .keyDown, triggerIsDown {
            return .nonTriggerKeyDown(timestampMs: event.timestampMs, isModifierOnly: false)
        }
        guard event.type == .flagsChanged else {
            return nil
        }
        if event.keyCode == leftKeyCode {
            return nil
        }
        if event.keyCode == rightKeyCode {
            if !triggerIsDown {
                guard (event.flags & flagMask) != 0 else {
                    return nil
                }
                triggerIsDown = true
                return .triggerDown(timestampMs: event.timestampMs)
            }
            triggerIsDown = false
            return .triggerUp(timestampMs: event.timestampMs)
        }
        if triggerIsDown {
            return .nonTriggerKeyDown(timestampMs: event.timestampMs, isModifierOnly: true)
        }
        return nil
    }

    private mutating func mapControlSpace(_ event: KeyboardEventSnapshot) -> TriggerEvent? {
        if event.type == .flagsChanged,
           triggerIsDown,
           (event.flags & TriggerKeyMatcher.controlFlagMask) == 0 {
            triggerIsDown = false
            return .triggerUp(timestampMs: event.timestampMs)
        }

        guard event.keyCode == TriggerKeyMatcher.spaceKeyCode else {
            if event.type == .keyDown, triggerIsDown {
                return .nonTriggerKeyDown(timestampMs: event.timestampMs, isModifierOnly: false)
            }
            return nil
        }

        switch event.type {
        case .keyDown:
            guard !event.isAutoRepeat,
                  !triggerIsDown,
                  (event.flags & TriggerKeyMatcher.controlFlagMask) != 0 else {
                return nil
            }
            triggerIsDown = true
            return .triggerDown(timestampMs: event.timestampMs)
        case .keyUp:
            guard triggerIsDown else {
                return nil
            }
            triggerIsDown = false
            return .triggerUp(timestampMs: event.timestampMs)
        case .flagsChanged:
            return nil
        }
    }
}
