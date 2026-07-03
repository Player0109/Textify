public enum HotkeyMonitorError: Error, Equatable, Sendable {
    case inputMonitoringDenied
    case eventTapCreationFailed
    case runLoopSourceCreationFailed
    case alreadyRunning
    case notRunning
}
