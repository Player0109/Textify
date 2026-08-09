public enum DictationSessionLimits {
    public static let maximumDurationSeconds: Double = 300
    public static let warningDurationSeconds = 10
}

public enum DictationSessionEndReason: String, Equatable, Sendable {
    case triggerReleased = "trigger_released"
    case sessionLimitReached = "session_limit_reached"
}

public enum DictationSessionProgress: Equatable, Sendable {
    case inactive
    case recording(deadlineUptimeMilliseconds: Int)
    case processing(
        completedWindows: Int,
        totalWindows: Int,
        endReason: DictationSessionEndReason
    )
}
