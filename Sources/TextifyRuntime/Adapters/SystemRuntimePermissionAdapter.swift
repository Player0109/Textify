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
            microphone: microphone.status() == .granted ? .granted : .denied,
            accessibility: accessibility.status() == .trusted ? .granted : .denied,
            inputMonitoring: inputMonitoringState()
        )
    }

    private func inputMonitoringState() -> RuntimePermissionState {
        inputMonitoring.status() == .granted ? .granted : .unknown
    }
}
