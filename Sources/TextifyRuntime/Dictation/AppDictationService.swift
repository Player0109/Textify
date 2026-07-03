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
    private var insertionSessionID: UUID?

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

    public var configuredTrigger: TriggerPreference {
        triggerStateMachine.trigger
    }

    @discardableResult
    public func refreshReadiness() async -> ReadinessSnapshot {
        let preferences = await dependencies.settings.loadPreferences()
        let permissions = await dependencies.permissions.permissionSnapshot()
        let activeModel = await dependencies.models.resolveActiveModel(preferences: preferences)
        let installedReadiness = await dependencies.models.readiness(for: activeModel)
        let modelReadiness = await effectiveModelReadiness(
            activeModel: activeModel,
            installedReadiness: installedReadiness
        )
        let snapshot = ReadinessSnapshot(
            permissions: permissions,
            model: modelReadiness
        )
        readiness = snapshot
        return snapshot
    }

    @discardableResult
    public func handleTriggerEvent(_ event: TriggerEvent) async -> TriggerAction {
        if case .triggerDown = event, !canStartActivation {
            return .none
        }

        let action = triggerStateMachine.handle(event)
        if case .triggerUp = event, action == .none, status == .waitingForActivation {
            activationTimerToken = nil
            resetTriggerStateMachine()
            status = .idle
        }
        if case .speechDetected = event,
           activeSessionID != nil,
           case .recording = status {
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
            guard canStartActivation else {
                return
            }
            startActivationTimer(delayMs: delayMs)
        case .beginRecording:
            await beginRecording()
        case .cancelAsShortcut:
            await cancelActiveSession(reason: .shortcutUseBeforeSpeech)
        case .cancelRecording:
            await cancelActiveSession(reason: .escapeKey)
        case .discardRecording:
            guard insertionSessionID == nil else {
                return
            }
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
        if insertionSessionID != nil {
            resetTriggerStateMachine()
            return
        }

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
        guard !hasActiveDictationWork else {
            return
        }

        let sessionID = UUID()
        activeSessionID = sessionID
        activationTimerToken = nil
        let snapshot = await refreshReadiness()
        guard activeSessionID == sessionID else {
            return
        }

        if let blocker = snapshot.blockers.first {
            activeSessionID = nil
            resetTriggerStateMachine()
            status = .blocked(.readinessBlocked(blocker))
            return
        }

        let preferences = await dependencies.settings.loadPreferences()
        guard activeSessionID == sessionID else {
            return
        }

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
                await dependencies.audio.discardRecording()
                return
            }
            status = .recording(speechDetected: false)
        } catch {
            guard activeSessionID == sessionID else {
                return
            }
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
        guard case .recording = status else {
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
            insertionSessionID = sessionID
            let outcome = await dependencies.inserter.insert(InsertionRequest(text: processed))
            guard activeSessionID == sessionID else {
                return
            }

            activeSessionID = nil
            insertionSessionID = nil
            switch outcome {
            case .pasted:
                status = .completed(textLengthBucket: Self.textLengthBucket(for: processed.count))
            case .notInserted:
                status = .failed(.insertionFailed)
            }
        } catch let error as LiveAudioRecorderError {
            guard activeSessionID == sessionID else {
                return
            }
            activeSessionID = nil
            insertionSessionID = nil
            status = Self.status(forAudioFinishError: error)
        } catch is WhisperRuntimeError {
            guard activeSessionID == sessionID else {
                return
            }
            activeSessionID = nil
            insertionSessionID = nil
            status = .failed(.transcriptionFailed)
        } catch {
            guard activeSessionID == sessionID else {
                return
            }
            activeSessionID = nil
            insertionSessionID = nil
            status = .failed(.transcriptionFailed)
        }
    }

    private var canStartActivation: Bool {
        !hasActiveDictationWork && status != .waitingForActivation
    }

    private var hasActiveDictationWork: Bool {
        if activeSessionID != nil || insertionSessionID != nil {
            return true
        }

        switch status {
        case .recording, .processing, .inserting:
            return true
        case .idle, .waitingForActivation, .completed, .cancelled, .blocked, .failed:
            return false
        }
    }

    private func effectiveModelReadiness(
        activeModel: RuntimeActiveModel?,
        installedReadiness: RuntimeModelReadiness
    ) async -> RuntimeModelReadiness {
        guard let activeModel else {
            return .noActiveModel
        }

        guard case .ready = installedReadiness else {
            return installedReadiness
        }

        let transcriberReadiness = await dependencies.transcriber.readiness
        switch transcriberReadiness {
        case let .loading(modelID),
             let .warming(modelID):
            return modelID == activeModel.id ? transcriberReadiness : installedReadiness
        case let .failed(modelID, _):
            return modelID == activeModel.id ? transcriberReadiness : installedReadiness
        case let .ready(modelID):
            return modelID == activeModel.id ? transcriberReadiness : installedReadiness
        case .noActiveModel, .missing:
            return installedReadiness
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

    private static func status(forAudioFinishError error: LiveAudioRecorderError) -> DictationRuntimeStatus {
        switch error {
        case .emptyRecording:
            return .cancelled(.noSpeechDetected)
        case .conversionFailed, .unsupportedInputFormat:
            return .failed(.audioConversionFailed)
        case .deviceChangedDuringRecording:
            return .failed(.microphoneChanged)
        case .microphonePermissionDenied,
             .unsupportedInput,
             .alreadyRecording,
             .notRecording,
             .inputNodeUnavailable,
             .engineStartFailed:
            return .failed(.audioFinishFailed)
        }
    }
}
