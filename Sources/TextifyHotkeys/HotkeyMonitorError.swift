public enum HotkeyMonitorError: Error, Equatable, Sendable {
    case inputMonitoringPermissionRequired
    case inputMonitoringDenied
    case eventTapDisabledByUserInput
    case eventTapCreationFailed
    case runLoopSourceCreationFailed
    case alreadyRunning
    case notRunning
}
