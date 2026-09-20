public enum TriggerEvent: Equatable, Sendable {
    case triggerDown(timestampMs: Int)
    case triggerUp(timestampMs: Int)
    case timerFired(timestampMs: Int)
    case nonTriggerKeyDown(timestampMs: Int, isModifierOnly: Bool)
    case speechDetected(timestampMs: Int)
    case escapeKeyDown(timestampMs: Int)
}

public enum TriggerAction: Equatable, Sendable {
    case none
    case beginArmedCapture(delayMs: Int)
    case activateRecording
    case beginRecording
    case cancelAsShortcut
    case cancelRecording
    case discardRecording
    case finishRecording
}
