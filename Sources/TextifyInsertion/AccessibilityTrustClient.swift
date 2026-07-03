import ApplicationServices

public enum AccessibilityTrustStatus: Equatable, Sendable {
    case trusted
    case notTrusted
}

public struct AccessibilityTrustClient: Sendable {
    private let statusClosure: @Sendable () -> AccessibilityTrustStatus

    public init(status: @escaping @Sendable () -> AccessibilityTrustStatus) {
        self.statusClosure = status
    }

    public func status() -> AccessibilityTrustStatus {
        statusClosure()
    }

    public static let live = AccessibilityTrustClient(
        status: {
            AXIsProcessTrusted() ? .trusted : .notTrusted
        }
    )
}
