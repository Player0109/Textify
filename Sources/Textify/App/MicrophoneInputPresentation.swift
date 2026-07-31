import Foundation
import Observation
import TextifyAudio
import TextifySettings

@MainActor
@Observable
final class MicrophoneInputPresentation {
    private(set) var devices: [MicrophoneDevice] = []
    private(set) var level: Float = 0
    private(set) var isMonitoring = false
    private(set) var monitoringError: LiveAudioRecorderError?
    private(set) var deviceRefreshFailed = false

    @ObservationIgnored private let client: MicrophoneInputClient
    @ObservationIgnored private var monitoringTask: Task<Void, Never>?
    @ObservationIgnored private var monitoredSelection: MicrophoneSelection?

    init(client: MicrophoneInputClient = .live) {
        self.client = client
    }

    func refreshDevices() {
        do {
            devices = try client.inputDevices().sorted {
                $0.displayName.localizedStandardCompare($1.displayName)
                    == .orderedAscending
            }
            deviceRefreshFailed = false
        } catch {
            devices = []
            deviceRefreshFailed = true
        }
    }

    func presentedDevices(
        selection: MicrophoneSelection
    ) -> [MicrophoneDevice] {
        guard case let .device(deviceUID, lastSeenDisplayName) = selection,
              !devices.contains(where: { $0.id == deviceUID })
        else {
            return devices
        }

        return devices + [
            MicrophoneDevice(
                id: deviceUID,
                displayName: lastSeenDisplayName,
                isAvailable: false
            ),
        ]
    }

    func startMonitoring(selection: MicrophoneSelection) {
        guard monitoredSelection != selection || monitoringTask == nil else {
            return
        }

        stopMonitoring()
        monitoredSelection = selection
        monitoringError = nil
        isMonitoring = true

        let stream = client.levelStream(for: selection.liveAudioInput)
        monitoringTask = Task { [weak self] in
            do {
                for try await level in stream {
                    guard !Task.isCancelled else {
                        return
                    }
                    self?.level = min(max(level, 0), 1)
                }
                guard !Task.isCancelled else {
                    return
                }
                self?.isMonitoring = false
                self?.monitoringTask = nil
                self?.monitoredSelection = nil
            } catch is CancellationError {
                return
            } catch let error as LiveAudioRecorderError {
                guard !Task.isCancelled else {
                    return
                }
                self?.level = 0
                self?.monitoringError = error
                if error == .selectedInputUnavailable {
                    self?.refreshDevices()
                }
                self?.isMonitoring = false
                self?.monitoringTask = nil
                self?.monitoredSelection = nil
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                self?.level = 0
                self?.monitoringError = .engineStartFailed
                self?.isMonitoring = false
                self?.monitoringTask = nil
                self?.monitoredSelection = nil
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        monitoredSelection = nil
        isMonitoring = false
        level = 0
    }
}

private extension MicrophoneSelection {
    var liveAudioInput: LiveAudioInput {
        switch self {
        case .systemDefault:
            return .systemDefault
        case let .device(deviceUID, _):
            return .device(deviceUID: deviceUID)
        }
    }
}
