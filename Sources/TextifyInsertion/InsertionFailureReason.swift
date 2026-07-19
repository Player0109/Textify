public enum InsertionFailureReason: Error, Equatable, Sendable {
    case emptyText
    case accessibilityNotTrusted
    case targetChanged
    case blockedTarget(InsertionTargetBlock)
    case pasteboardSnapshotFailed
    case pasteboardWriteFailed
    case pasteEventFailed
    case typingFallbackFailed
}
