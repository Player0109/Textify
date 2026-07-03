@preconcurrency import AVFoundation

public enum MicrophonePermissionStatus: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
}

public struct MicrophonePermissionClient: Sendable {
    private let statusClosure: @Sendable () -> MicrophonePermissionStatus
    private let requestClosure: @Sendable () async -> MicrophonePermissionStatus

    public init(
        status: @escaping @Sendable () -> MicrophonePermissionStatus,
        requestAccess: @escaping @Sendable () async -> MicrophonePermissionStatus
    ) {
        self.statusClosure = status
        self.requestClosure = requestAccess
    }

    public func status() -> MicrophonePermissionStatus {
        statusClosure()
    }

    public func requestAccess() async -> MicrophonePermissionStatus {
        await requestClosure()
    }

    public static let live = MicrophonePermissionClient(
        status: {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                return .granted
            case .notDetermined:
                return .notDetermined
            case .denied:
                return .denied
            case .restricted:
                return .restricted
            @unknown default:
                return .denied
            }
        },
        requestAccess: {
            await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted ? .granted : .denied)
                }
            }
        }
    )
}
