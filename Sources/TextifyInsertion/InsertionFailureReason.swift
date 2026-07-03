public enum InsertionFailureReason: Error, Equatable, Sendable {
    case emptyText
    case accessibilityNotTrusted
    case blockedTarget(InsertionTargetBlock)
    case pasteboardSnapshotFailed
    case pasteboardWriteFailed
    case pasteEventFailed
}
