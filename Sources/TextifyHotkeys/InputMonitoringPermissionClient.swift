import CoreGraphics

public enum InputMonitoringPermissionStatus: Equatable, Sendable {
    case unknown
    case granted
    case denied
}

public struct InputMonitoringPermissionClient: Sendable {
    private let statusClosure: @Sendable () -> InputMonitoringPermissionStatus
    private let requestClosure: @Sendable () async -> InputMonitoringPermissionStatus

    public init(
        status: @escaping @Sendable () -> InputMonitoringPermissionStatus,
        requestAccess: @escaping @Sendable () async -> InputMonitoringPermissionStatus
    ) {
        self.statusClosure = status
        self.requestClosure = requestAccess
    }

    public func status() -> InputMonitoringPermissionStatus {
        statusClosure()
    }

    public func requestAccess() async -> InputMonitoringPermissionStatus {
        await requestClosure()
    }

    public static let live = InputMonitoringPermissionClient(
        status: {
            CGPreflightListenEventAccess() ? .granted : .unknown
        },
        requestAccess: {
            InputMonitoringPermissionClient.requestResult(
                wasGranted: CGRequestListenEventAccess()
            )
        }
    )

    static func requestResult(wasGranted: Bool) -> InputMonitoringPermissionStatus {
        wasGranted ? .granted : .unknown
    }
}
