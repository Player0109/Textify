public enum DictationEvent: Equatable, Sendable {
    case triggerDown(timestampMs: Int)
    case activationThresholdPassed(timestampMs: Int)
    case triggerUp(timestampMs: Int)
    case nonTriggerKeyDown(timestampMs: Int, isModifierOnly: Bool)
    case escapeKeyDown(timestampMs: Int)
    case speechDetected(timestampMs: Int)
}
