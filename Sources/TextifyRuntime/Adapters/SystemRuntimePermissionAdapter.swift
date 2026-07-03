import TextifyAudio
import TextifyHotkeys
import TextifyInsertion

public struct SystemRuntimePermissionAdapter: RuntimePermissionChecking {
    private let microphone: MicrophonePermissionClient
    private let inputMonitoring: InputMonitoringPermissionClient
    private let accessibility: AccessibilityTrustClient

    public init(
        microphone: MicrophonePermissionClient = .live,
        inputMonitoring: InputMonitoringPermissionClient = .live,
        accessibility: AccessibilityTrustClient = .live
    ) {
        self.microphone = microphone
        self.inputMonitoring = inputMonitoring
        self.accessibility = accessibility
    }

    public func permissionSnapshot() async -> RuntimePermissionSnapshot {
        RuntimePermissionSnapshot(
            microphone: microphoneState(),
            accessibility: accessibility.status() == .trusted ? .granted : .denied,
            inputMonitoring: inputMonitoringState()
        )
    }

    private func microphoneState() -> RuntimePermissionState {
        switch microphone.status() {
        case .granted:
            return .granted
        case .notDetermined:
            return .unknown
        case .denied, .restricted:
            return .denied
        }
    }

    private func inputMonitoringState() -> RuntimePermissionState {
        inputMonitoring.status() == .granted ? .granted : .unknown
    }
}
