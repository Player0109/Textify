import Foundation
import Observation
import TextifyAudio
import TextifyHotkeys
import TextifyInsertion
import TextifyTranscription

@MainActor
@Observable
public final class AppDictationService {
    public private(set) var status: DictationRuntimeStatus
    public private(set) var readiness: ReadinessSnapshot

    private let dependencies: RuntimeDependencies
    private var triggerStateMachine: TriggerStateMachine
    private var activationTimerToken: UUID?
    private var activeSessionID: UUID?

    public init(
        dependencies: RuntimeDependencies,
        triggerStateMachine: TriggerStateMachine = TriggerStateMachine()
    ) {
        self.dependencies = dependencies
        self.triggerStateMachine = triggerStateMachine
        self.status = .idle
        self.readiness = ReadinessSnapshot(
            permissions: RuntimePermissionSnapshot(
                microphone: .unknown,
                accessibility: .unknown,
                inputMonitoring: .unknown
            ),
            model: .noActiveModel
        )
    }

    @discardableResult
    public func refreshReadiness() async -> ReadinessSnapshot {
        let preferences = await dependencies.settings.loadPreferences()
        let permissions = await dependencies.permissions.permissionSnapshot()
        let activeModel = await dependencies.models.resolveActiveModel(preferences: preferences)
        let modelReadiness = await dependencies.models.readiness(for: activeModel)
        let snapshot = ReadinessSnapshot(
            permissions: permissions,
            model: modelReadiness
        )
        readiness = snapshot
        return snapshot
    }

    @discardableResult
    public func handleTriggerEvent(_ event: TriggerEvent) async -> TriggerAction {
        let action = triggerStateMachine.handle(event)
        if case .speechDetected = event, activeSessionID != nil {
            status = .recording(speechDetected: true)
        }
        await handleTriggerAction(action)
        return action
    }

    public func handleTriggerAction(_ action: TriggerAction) async {
        switch action {
        case .none:
            return
        case let .startActivationTimer(delayMs):
            startActivationTimer(delayMs: delayMs)
        case .beginRecording:
            await beginRecording()
        case .cancelAsShortcut:
            await cancelActiveSession(reason: .shortcutUseBeforeSpeech)
        case .cancelRecording:
            await cancelActiveSession(reason: .escapeKey)
        case .discardRecording:
            activationTimerToken = nil
            activeSessionID = nil
            resetTriggerStateMachine()
            await dependencies.audio.discardRecording()
            status = .cancelled(.noSpeechDetected)
        case .finishRecording:
            await finishRecording()
        }
    }

    public func cancelActiveSession(reason: DictationCancellationReason) async {
        activationTimerToken = nil
        activeSessionID = nil
        resetTriggerStateMachine()
        await dependencies.audio.discardRecording()
        status = .cancelled(reason)
    }

    private func startActivationTimer(delayMs: Int) {
        let token = UUID()
        activationTimerToken = token
        status = .waitingForActivation

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await self.dependencies.clock.sleep(milliseconds: delayMs)
            guard self.activationTimerToken == token else {
                return
            }

            _ = await self.handleTriggerEvent(
                .timerFired(timestampMs: self.dependencies.clock.nowMilliseconds())
            )
        }
    }

    private func beginRecording() async {
        activationTimerToken = nil
        let snapshot = await refreshReadiness()
        if let blocker = snapshot.blockers.first {
            activeSessionID = nil
            resetTriggerStateMachine()
            status = .blocked(.readinessBlocked(blocker))
            return
        }

        let preferences = await dependencies.settings.loadPreferences()
        let sessionID = UUID()
        activeSessionID = sessionID

        do {
            try await dependencies.audio.startRecording(
                microphone: preferences.microphoneSelection
            ) { [weak self] in
                Task { @MainActor in
                    guard let self, self.activeSessionID == sessionID else {
                        return
                    }

                    _ = await self.handleTriggerEvent(
                        .speechDetected(timestampMs: self.dependencies.clock.nowMilliseconds())
                    )
                }
            }

            guard activeSessionID == sessionID else {
                return
            }
            status = .recording(speechDetected: false)
        } catch {
            activeSessionID = nil
            resetTriggerStateMachine()
            status = .failed(.audioStartFailed)
        }
    }

    private func finishRecording() async {
        guard let sessionID = activeSessionID else {
            status = .idle
            return
        }

        activationTimerToken = nil
        status = .processing

        do {
            let audio = try await dependencies.audio.finishRecording()
            guard activeSessionID == sessionID else {
                return
            }
            guard !audio.isEmpty else {
                activeSessionID = nil
                status = .cancelled(.noSpeechDetected)
                return
            }

            let preferences = await dependencies.settings.loadPreferences()
            guard activeSessionID == sessionID else {
                return
            }
            guard let activeModel = await dependencies.models.resolveActiveModel(preferences: preferences) else {
                activeSessionID = nil
                status = .blocked(.readinessBlocked(.noActiveModel))
                return
            }

            try await dependencies.transcriber.prepare(model: activeModel)
            guard activeSessionID == sessionID else {
                return
            }

            let transcriptionAudio = TranscriptionAudioBuffer(
                sampleRate: audio.sampleRate,
                channelCount: audio.channelCount,
                samples: audio.samples
            )
            let result = try await dependencies.transcriber.transcribe(transcriptionAudio)
            guard activeSessionID == sessionID else {
                return
            }

            let processed = await dependencies.postProcessor
                .process(rawText: result.text, preferences: preferences)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard activeSessionID == sessionID else {
                return
            }
            guard !processed.isEmpty else {
                activeSessionID = nil
                status = .idle
                return
            }

            status = .inserting
            let outcome = await dependencies.inserter.insert(InsertionRequest(text: processed))
            guard activeSessionID == sessionID else {
                return
            }

            activeSessionID = nil
            switch outcome {
            case .pasted:
                status = .completed(textLengthBucket: Self.textLengthBucket(for: processed.count))
            case .notInserted:
                status = .failed(.insertionFailed)
            }
        } catch let error as LiveAudioRecorderError {
            activeSessionID = nil
            status = error == .emptyRecording ? .cancelled(.noSpeechDetected) : .failed(.audioFinishFailed)
        } catch is WhisperRuntimeError {
            activeSessionID = nil
            status = .failed(.transcriptionFailed)
        } catch {
            activeSessionID = nil
            status = .failed(.transcriptionFailed)
        }
    }

    private func resetTriggerStateMachine() {
        triggerStateMachine = TriggerStateMachine(
            trigger: triggerStateMachine.trigger,
            activationDelayMs: triggerStateMachine.activationDelayMs
        )
    }

    private static func textLengthBucket(for count: Int) -> String {
        switch count {
        case 0:
            return "0"
        case 1...50:
            return "1-50"
        case 51...200:
            return "51-200"
        case 201...500:
            return "201-500"
        default:
            return "501+"
        }
    }
}
