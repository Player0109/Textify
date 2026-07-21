import Foundation
import Observation
import TextifyAudio
import TextifyCore
import TextifyDiagnostics
import TextifyHotkeys
import TextifyInsertion
import TextifySettings
import TextifyTranscription

@MainActor
@Observable
public final class AppDictationService {
    public private(set) var status: DictationRuntimeStatus
    public private(set) var readiness: ReadinessSnapshot
    public private(set) var voiceCleaningStatus: VoiceCleaningRuntimeStatus

    private let dependencies: RuntimeDependencies
    private var triggerStateMachine: TriggerStateMachine
    private var activationTimerToken: UUID?
    private var targetCaptureToken: UUID?
    private var activationTarget: InsertionTargetIdentity?
    private var excludedTriggerIsHeld = false
    private var activeSessionID: UUID?
    private var insertionSessionID: UUID?

    public init(
        dependencies: RuntimeDependencies,
        triggerStateMachine: TriggerStateMachine = TriggerStateMachine()
    ) {
        self.dependencies = dependencies
        self.triggerStateMachine = triggerStateMachine
        self.status = .idle
        self.voiceCleaningStatus = .disabled
        self.readiness = ReadinessSnapshot(
            permissions: RuntimePermissionSnapshot(
                microphone: .unknown,
                accessibility: .unknown,
                inputMonitoring: .unknown
            ),
            model: .noActiveModel
        )
    }

    public var configuredTrigger: TextifyHotkeys.TriggerPreference {
        triggerStateMachine.trigger
    }

    @discardableResult
    public func updateConfiguredTrigger(_ trigger: TextifyHotkeys.TriggerPreference) -> Bool {
        guard !hasActiveDictationWork, status != .waitingForActivation else {
            return false
        }
        activationTimerToken = nil
        targetCaptureToken = nil
        activationTarget = nil
        excludedTriggerIsHeld = false
        triggerStateMachine = TriggerStateMachine(
            trigger: trigger,
            activationDelayMs: triggerStateMachine.activationDelayMs
        )
        status = .idle
        return true
    }

    @discardableResult
    public func prepareActiveModelIfAvailable() async -> ReadinessSnapshot {
        let preferences = await dependencies.settings.loadPreferences()
        let activeModel = await dependencies.models.resolveActiveModel(preferences: preferences)
        let installedReadiness = await dependencies.models.readiness(for: activeModel)

        if let activeModel, case .ready = installedReadiness {
            let startedAt = dependencies.clock.nowMilliseconds()
            do {
                try await dependencies.transcriber.prepare(model: activeModel)
                await dependencies.diagnostics.log(
                    .modelLoad(
                        modelID: activeModel.id,
                        tier: activeModel.tier,
                        engine: activeModel.engine.rawValue,
                        accelerator: activeModel.accelerator.rawValue,
                        durationMs: max(0, dependencies.clock.nowMilliseconds() - startedAt),
                        result: "ready"
                    )
                )
            } catch {
                await dependencies.diagnostics.log(
                    .modelLoad(
                        modelID: activeModel.id,
                        tier: activeModel.tier,
                        engine: activeModel.engine.rawValue,
                        accelerator: activeModel.accelerator.rawValue,
                        durationMs: max(0, dependencies.clock.nowMilliseconds() - startedAt),
                        result: "failed"
                    )
                )
            }
        }

        await prepareVoiceCleaner(preferences: preferences)

        return await refreshReadiness()
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
        switch event {
        case .triggerUp, .nonTriggerKeyDown, .escapeKeyDown:
            targetCaptureToken = nil
            activationTarget = nil
        case .triggerDown, .timerFired, .speechDetected:
            break
        }

        if case .triggerDown = event {
            guard canStartActivation else {
                return .none
            }
            guard await captureTargetAtKeyDown() else {
                return .none
            }
        }
        if case .triggerUp = event, excludedTriggerIsHeld {
            targetCaptureToken = nil
            activationTarget = nil
            excludedTriggerIsHeld = false
            status = .idle
            return .none
        }

        let action = triggerStateMachine.handle(event)
        if case .triggerUp = event, action == .none, status == .waitingForActivation {
            activationTimerToken = nil
            targetCaptureToken = nil
            activationTarget = nil
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
            targetCaptureToken = nil
            activationTarget = nil
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
        targetCaptureToken = nil
        activationTarget = nil
        excludedTriggerIsHeld = false
        if insertionSessionID != nil {
            resetTriggerStateMachine()
            return
        }

        activeSessionID = nil
        resetTriggerStateMachine()
        await dependencies.audio.discardRecording()
        status = .cancelled(reason)
    }

    public func dismissTerminalStatus() {
        switch status {
        case .completed, .cancelled, .failed:
            status = .idle
        case .blocked(.excludedApp):
            break
        case .blocked:
            status = .idle
        case .idle, .waitingForActivation, .recording, .processing, .inserting:
            break
        }
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

        if activationTarget == nil {
            activationTarget = await dependencies.targetCapturer.currentTargetIdentity()
        }
        guard let capturedTarget = activationTarget else {
            resetTriggerStateMachine()
            status = .idle
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
            activationTarget = nil
            resetTriggerStateMachine()
            status = .blocked(.readinessBlocked(blocker))
            return
        }

        let preferences = await dependencies.settings.loadPreferences()
        guard activeSessionID == sessionID else {
            return
        }
        if Self.isExcluded(capturedTarget, by: preferences) {
            activeSessionID = nil
            self.activationTarget = nil
            resetTriggerStateMachine()
            status = .blocked(.excludedApp)
            return
        }
        guard let activeModel = await dependencies.models.resolveActiveModel(preferences: preferences) else {
            activeSessionID = nil
            activationTarget = nil
            resetTriggerStateMachine()
            status = .blocked(.readinessBlocked(.noActiveModel))
            return
        }

        do {
            try await dependencies.audio.startRecording(
                microphone: preferences.microphoneSelection,
                maximumDurationSeconds: Double(activeModel.runtimeParameters.maxAudioSeconds),
                onSpeechDetected: { [weak self] in
                    Task { @MainActor in
                        guard let self, self.activeSessionID == sessionID else {
                            return
                        }

                        _ = await self.handleTriggerEvent(
                            .speechDetected(timestampMs: self.dependencies.clock.nowMilliseconds())
                        )
                    }
                },
                onMaximumDurationReached: { [weak self] in
                    Task { @MainActor in
                        guard let self, self.activeSessionID == sessionID else {
                            return
                        }
                        await self.handleTriggerAction(.finishRecording)
                    }
                }
            )

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
            activationTarget = nil
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
                activationTarget = nil
                status = .cancelled(.noSpeechDetected)
                return
            }

            let preferences = await dependencies.settings.loadPreferences()
            guard activeSessionID == sessionID else {
                return
            }
            guard let activeModel = await dependencies.models.resolveActiveModel(preferences: preferences) else {
                activeSessionID = nil
                activationTarget = nil
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
            let preparedAudio = await voiceCleanedAudio(
                transcriptionAudio,
                preferences: preferences
            )
            let inferenceStartedAt = dependencies.clock.nowMilliseconds()
            let result = try await dependencies.transcriber.transcribe(preparedAudio)
            let inferenceDurationMs = max(
                0,
                dependencies.clock.nowMilliseconds() - inferenceStartedAt
            )
            guard activeSessionID == sessionID else {
                return
            }
            let shouldDiscard = HallucinationFilter().shouldDiscard(
                text: result.text,
                noSpeechProbability: result.noSpeechProbability,
                averageLogProbability: result.averageLogProbability,
                compressionRatio: result.compressionRatio
            )
            if shouldDiscard {
                await dependencies.diagnostics.log(
                    .transcriptionDiscarded(
                        modelID: activeModel.id,
                        noSpeechProbability: result.noSpeechProbability,
                        averageLogProbability: result.averageLogProbability,
                        compressionRatio: result.compressionRatio
                    )
                )
                activeSessionID = nil
                activationTarget = nil
                status = .idle
                return
            }
            await dependencies.diagnostics.log(
                .transcriptionCompleted(
                    modelID: activeModel.id,
                    engine: activeModel.engine.rawValue,
                    accelerator: activeModel.accelerator.rawValue,
                    backendReadiness: "ready",
                    audioDurationMs: max(0, Int(audio.durationSeconds * 1_000)),
                    inferenceDurationMs: inferenceDurationMs,
                    textLengthBucket: Self.textLengthBucket(for: result.text.count)
                )
            )

            let processed = await dependencies.postProcessor
                .process(rawText: result.text, preferences: preferences)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard activeSessionID == sessionID else {
                return
            }
            guard !processed.isEmpty else {
                activeSessionID = nil
                activationTarget = nil
                status = .idle
                return
            }

            status = .inserting
            insertionSessionID = sessionID
            let insertionStartedAt = dependencies.clock.nowMilliseconds()
            let outcome = await dependencies.inserter.insert(
                InsertionRequest(text: processed, target: activationTarget)
            )
            await dependencies.diagnostics.log(
                Self.insertionDiagnosticEvent(
                    outcome: outcome,
                    textLengthBucket: Self.textLengthBucket(for: processed.count),
                    durationMs: max(
                        0,
                        dependencies.clock.nowMilliseconds() - insertionStartedAt
                    )
                )
            )
            guard activeSessionID == sessionID else {
                return
            }

            activeSessionID = nil
            insertionSessionID = nil
            self.activationTarget = nil
            switch outcome {
            case .pasted, .typed:
                status = .completed(textLengthBucket: Self.textLengthBucket(for: processed.count))
            case .notInserted(.targetChanged):
                status = .idle
            case .notInserted(.blockedTarget):
                status = .idle
            case .notInserted:
                status = .failed(.insertionFailed)
            }
        } catch let error as LiveAudioRecorderError {
            guard activeSessionID == sessionID else {
                return
            }
            activeSessionID = nil
            insertionSessionID = nil
            activationTarget = nil
            status = Self.status(forAudioFinishError: error)
        } catch is WhisperRuntimeError {
            guard activeSessionID == sessionID else {
                return
            }
            activeSessionID = nil
            insertionSessionID = nil
            activationTarget = nil
            status = .failed(.transcriptionFailed)
        } catch {
            guard activeSessionID == sessionID else {
                return
            }
            activeSessionID = nil
            insertionSessionID = nil
            activationTarget = nil
            status = .failed(.transcriptionFailed)
        }
    }

    private func prepareVoiceCleaner(preferences: AppPreferences) async {
        guard let selectedModelID = preferences.activeVoiceCleaningModelID else {
            await dependencies.voiceCleaner.unload()
            voiceCleaningStatus = .disabled
            return
        }
        guard let model = await dependencies.models.resolveActiveVoiceCleaningModel(
            preferences: preferences
        ), case .ready = await dependencies.models.readiness(for: model) else {
            await dependencies.voiceCleaner.unload()
            voiceCleaningStatus = .warning(
                modelID: selectedModelID,
                reason: .modelUnavailable
            )
            return
        }

        voiceCleaningStatus = .preparing(modelID: model.id)
        let startedAt = dependencies.clock.nowMilliseconds()
        do {
            try await dependencies.voiceCleaner.prepare(model: model)
            voiceCleaningStatus = .ready(modelID: model.id)
            await dependencies.diagnostics.log(
                .voiceCleaning(
                    modelID: model.id,
                    durationMs: max(0, dependencies.clock.nowMilliseconds() - startedAt),
                    result: "ready"
                )
            )
        } catch {
            voiceCleaningStatus = .warning(modelID: model.id, reason: .modelUnavailable)
            await dependencies.diagnostics.log(
                .voiceCleaning(
                    modelID: model.id,
                    durationMs: max(0, dependencies.clock.nowMilliseconds() - startedAt),
                    result: "raw_audio_fallback"
                )
            )
        }
    }

    private func voiceCleanedAudio(
        _ audio: TranscriptionAudioBuffer,
        preferences: AppPreferences
    ) async -> TranscriptionAudioBuffer {
        guard let selectedModelID = preferences.activeVoiceCleaningModelID else {
            if voiceCleaningStatus != .disabled {
                await dependencies.voiceCleaner.unload()
                voiceCleaningStatus = .disabled
            }
            return audio
        }
        guard let model = await dependencies.models.resolveActiveVoiceCleaningModel(
            preferences: preferences
        ), case .ready = await dependencies.models.readiness(for: model) else {
            await dependencies.voiceCleaner.unload()
            voiceCleaningStatus = .warning(modelID: selectedModelID, reason: .modelUnavailable)
            return audio
        }

        let startedAt = dependencies.clock.nowMilliseconds()
        do {
            try await dependencies.voiceCleaner.prepare(model: model)
            let cleaned = try await dependencies.voiceCleaner.clean(audio)
            voiceCleaningStatus = .ready(modelID: model.id)
            await dependencies.diagnostics.log(
                .voiceCleaning(
                    modelID: model.id,
                    durationMs: max(0, dependencies.clock.nowMilliseconds() - startedAt),
                    result: "cleaned"
                )
            )
            return cleaned
        } catch {
            voiceCleaningStatus = .warning(modelID: model.id, reason: .processingFailed)
            await dependencies.diagnostics.log(
                .voiceCleaning(
                    modelID: model.id,
                    durationMs: max(0, dependencies.clock.nowMilliseconds() - startedAt),
                    result: "raw_audio_fallback"
                )
            )
            return audio
        }
    }

    private var canStartActivation: Bool {
        targetCaptureToken == nil && !hasActiveDictationWork && status != .waitingForActivation
    }

    private func captureTargetAtKeyDown() async -> Bool {
        let token = UUID()
        targetCaptureToken = token
        let target = await dependencies.targetCapturer.currentTargetIdentity()
        guard targetCaptureToken == token else {
            return false
        }
        guard let target else {
            targetCaptureToken = nil
            return false
        }

        let preferences = await dependencies.settings.loadPreferences()
        guard targetCaptureToken == token else {
            return false
        }
        targetCaptureToken = nil
        guard !Self.isExcluded(target, by: preferences) else {
            activationTarget = nil
            excludedTriggerIsHeld = true
            status = .blocked(.excludedApp)
            Task { [diagnostics = dependencies.diagnostics] in
                await diagnostics.log(.dictationBlockedExcludedApp)
            }
            return false
        }

        activationTarget = target
        excludedTriggerIsHeld = false
        return true
    }

    private static func isExcluded(
        _ target: InsertionTargetIdentity,
        by preferences: AppPreferences
    ) -> Bool {
        guard let bundleIdentifier = target.bundleIdentifier else {
            return false
        }
        return preferences.excludedApps.contains {
            $0.bundleIdentifier == bundleIdentifier
        }
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

    private static func insertionDiagnosticEvent(
        outcome: InsertionOutcome,
        textLengthBucket: String,
        durationMs: Int
    ) -> DiagnosticEvent {
        let snapshotSucceeded: Bool
        let writeSucceeded: Bool
        let pastePosted: Bool
        let fallbackAttempted: Bool
        let fallbackBlockedReason: String?

        switch outcome {
        case .pasted:
            snapshotSucceeded = true
            writeSucceeded = true
            pastePosted = true
            fallbackAttempted = false
            fallbackBlockedReason = nil
        case let .typed(report):
            switch report.cause {
            case .pasteboardSnapshotUnavailable:
                snapshotSucceeded = false
                writeSucceeded = false
            case .pasteEventUnavailable:
                snapshotSucceeded = true
                writeSucceeded = true
            }
            pastePosted = false
            fallbackAttempted = true
            fallbackBlockedReason = nil
        case let .notInserted(reason):
            snapshotSucceeded = reason != .pasteboardSnapshotFailed
            writeSucceeded = ![.pasteboardSnapshotFailed, .pasteboardWriteFailed].contains(reason)
            pastePosted = false
            fallbackAttempted = reason == .typingFallbackFailed
            switch reason {
            case .targetChanged:
                fallbackBlockedReason = "target_changed"
            case .blockedTarget:
                fallbackBlockedReason = "secure_field_detected"
            case .emptyText:
                fallbackBlockedReason = "empty_text"
            default:
                fallbackBlockedReason = nil
            }
        }

        return .insertionAttempt(
            textLengthBucket: textLengthBucket,
            pasteboardSnapshotSucceeded: snapshotSucceeded,
            pasteboardWriteSucceeded: writeSucceeded,
            pasteEventPosted: pastePosted,
            fallbackAttempted: fallbackAttempted,
            fallbackBlockedReason: fallbackBlockedReason,
            durationMs: durationMs
        )
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
