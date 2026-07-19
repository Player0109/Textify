public enum HotkeyMonitorError: Error, Equatable, Sendable {
    case eventTapDisabledByUserInput
    case eventTapCreationFailed
    case runLoopSourceCreationFailed
    case alreadyRunning
    case notRunning
}
