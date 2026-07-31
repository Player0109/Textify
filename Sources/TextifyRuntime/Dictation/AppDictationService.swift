import Foundation
import Observation
import TextifyAudio
import TextifyCore
import TextifyDiagnostics
import TextifyHotkeys
import TextifyInsertion
import TextifyModels
import TextifySettings
import TextifyTranscription

@MainActor
@Observable
public final class AppDictationService {
    public private(set) var status: DictationRuntimeStatus
    public private(set) var readiness: ReadinessSnapshot
    public private(set) var voiceCleaningStatus: VoiceCleaningRuntimeStatus
    public private(set) var currentSegment: RuntimeCurrentSegment? {
        didSet {
            resumeCurrentSegmentWaiters()
        }
    }

    private let dependencies: RuntimeDependencies
    private var triggerStateMachine: TriggerStateMachine
    private var activationTimerToken: UUID?
    private var targetCaptureToken: UUID?
    private var activationTarget: InsertionTargetIdentity?
    private var excludedTriggerIsHeld = false
    private var activeSessionID: UUID?
    private var activeSessionPreferences:
        (sessionID: UUID, preferences: AppPreferences)?
    private var activeSegmentContext: (
        sessionID: UUID,
        transcriptionModel: RuntimeActiveModel,
        voiceCleaningModel: RuntimeActiveModel?
    )?
    private var insertionSessionID: UUID?
    private var revokedArtifactIDs: Set<String> = []
    private var modelTransactionInProgress = false
    private var pendingPurposeRuntimeTransactions = 0
    private var purposeRuntimeBoundaryReserved = false
    private var purposeRuntimeBoundaryWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var modelTransactionWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var currentSegmentWaiters: [CurrentSegmentWaiter] = []

    public init(
        dependencies: RuntimeDependencies,
        triggerStateMachine: TriggerStateMachine = TriggerStateMachine()
    ) {
        self.dependencies = dependencies
        self.triggerStateMachine = triggerStateMachine
        self.status = .idle
        self.voiceCleaningStatus = .disabled
        self.currentSegment = nil
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

    public var allowsModelTransactions: Bool {
        if modelTransactionInProgress
            || pendingPurposeRuntimeTransactions > 0 {
            return false
        }
        if case .processing = status {
            return false
        }
        return true
    }

    public func performPurposeRuntimeTransaction<Result>(
        waitingForCurrentSegmentUsing artifactID: String? = nil,
        waitingForCurrentSegmentIn purpose: ModelPurpose? = nil,
        _ operation: @MainActor () async throws -> Result
    ) async rethrows -> Result {
        pendingPurposeRuntimeTransactions += 1
        await reservePurposeRuntimeBoundary()
        defer {
            pendingPurposeRuntimeTransactions -= 1
            releasePurposeRuntimeBoundary()
        }
        let ownedArtifactID: String? = if let artifactID {
            artifactID
        } else {
            switch purpose {
            case .transcription:
                currentSegment?.transcriptionArtifactID
            case .voiceCleaning:
                currentSegment?.voiceCleaningArtifactID
            case nil:
                nil
            }
        }
        if let ownedArtifactID {
            await waitForCurrentSegmentToRelease(ownedArtifactID)
        }
        await waitForModelTransaction()
        modelTransactionInProgress = true
        defer { finishModelTransaction() }
        return try await operation()
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
        guard allowsModelTransactions else {
            return readiness
        }
        return await performPurposeRuntimeTransaction {
            await self.prepareActiveModelAtPurposeRuntimeBoundary()
        }
    }

    @discardableResult
    public func prepareActiveModelAtPurposeRuntimeBoundary()
        async -> ReadinessSnapshot {
        guard modelTransactionInProgress else {
            return readiness
        }
        let preferences = await dependencies.settings.loadPreferences()
        let activeModel = await dependencies.models.resolveActiveModel(preferences: preferences)
        let installedReadiness = await dependencies.models.readiness(for: activeModel)

        if let activeModel, case .ready = installedReadiness {
            guard !revokedArtifactIDs.contains(activeModel.id) else {
                await prepareVoiceCleaner(preferences: preferences)
                return await refreshReadiness()
            }
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
                await logRuntimeFailure(
                    error,
                    model: activeModel,
                    stage: "model_prepare"
                )
            }
        }

        await prepareVoiceCleaner(preferences: preferences)

        return await refreshReadiness()
    }

    public func prepareModelSelection(
        modelID: String,
        purpose: ModelPurpose,
        preferences: AppPreferences
    ) async -> RuntimeModelPreparationResult {
        guard allowsModelTransactions else {
            return .busy(modelID: modelID)
        }
        return await performPurposeRuntimeTransaction {
            await self.prepareModelSelectionAtPurposeRuntimeBoundary(
                modelID: modelID,
                purpose: purpose,
                preferences: preferences
            )
        }
    }

    public func prepareModelSelectionAtPurposeRuntimeBoundary(
        modelID: String,
        purpose: ModelPurpose,
        preferences: AppPreferences
    ) async -> RuntimeModelPreparationResult {
        guard modelTransactionInProgress else {
            return .busy(modelID: modelID)
        }
        guard let model = await resolvedModelSelection(
            purpose: purpose,
            preferences: preferences
        ),
              model.id == modelID,
              model.purpose == purpose
        else {
            return .needsRepair(
                modelID: modelID,
                readiness: .missing(modelID: modelID)
            )
        }
        guard !revokedArtifactIDs.contains(model.id) else {
            return .revoked(modelID: modelID)
        }

        let installedReadiness = await dependencies.models.readiness(for: model)
        guard case .ready(modelID: modelID) = installedReadiness else {
            return .needsRepair(
                modelID: modelID,
                readiness: installedReadiness
            )
        }

        do {
            switch purpose {
            case .transcription:
                try await dependencies.transcriber.prepare(model: model)
                guard case .ready(modelID: modelID) =
                    await dependencies.transcriber.readiness
                else {
                    return .failed(modelID: modelID)
                }
            case .voiceCleaning:
                try await dependencies.voiceCleaner.prepare(model: model)
            }
            guard !revokedArtifactIDs.contains(model.id) else {
                return .revoked(modelID: modelID)
            }
            return .ready(modelID: modelID)
        } catch {
            return .failed(modelID: modelID)
        }
    }

    public func releaseArtifactForRemovalAtPurposeRuntimeBoundary(
        artifactID: String,
        purpose: ModelPurpose,
        wasPurposeActive: Bool
    ) async {
        guard modelTransactionInProgress,
              currentSegment?.owns(artifactID: artifactID) != true
        else {
            return
        }
        switch purpose {
        case .transcription:
            let readiness = await dependencies.transcriber.readiness
            let loadedArtifactMatches: Bool
            if case let .ready(modelID) = readiness {
                loadedArtifactMatches = modelID == artifactID
            } else {
                loadedArtifactMatches = false
            }
            if wasPurposeActive || loadedArtifactMatches {
                await dependencies.transcriber.unload()
            }
        case .voiceCleaning:
            let loadedModelID: String? = switch voiceCleaningStatus {
            case let .preparing(modelID),
                 let .ready(modelID),
                 let .warning(modelID, _):
                modelID
            case .disabled:
                nil
            }
            if wasPurposeActive || loadedModelID == artifactID {
                await dependencies.voiceCleaner.unload()
                voiceCleaningStatus = .disabled
            }
        }
    }

    public func modelReadiness(
        modelID: String,
        purpose: ModelPurpose,
        preferences: AppPreferences
    ) async -> RuntimeModelReadiness {
        guard let model = await resolvedModelSelection(
            purpose: purpose,
            preferences: preferences
        ),
              model.id == modelID,
              model.purpose == purpose
        else {
            return .missing(modelID: modelID)
        }
        guard !revokedArtifactIDs.contains(model.id) else {
            return .revoked(modelID: modelID)
        }
        return await dependencies.models.readiness(for: model)
    }

    public func updateRevokedArtifactIDs(
        _ artifactIDs: Set<String>
    ) async {
        guard artifactIDs != revokedArtifactIDs else {
            return
        }
        revokedArtifactIDs = artifactIDs
        let preferences = await dependencies.settings.loadPreferences()
        if let cleanerID = preferences.activeVoiceCleaningModelID,
           artifactIDs.contains(cleanerID),
           currentSegment?.voiceCleaningArtifactID != cleanerID {
            await dependencies.voiceCleaner.unload()
            voiceCleaningStatus = .warning(
                modelID: cleanerID,
                reason: .revoked
            )
        }
        _ = await refreshReadiness()
    }

    private func resolvedModelSelection(
        purpose: ModelPurpose,
        preferences: AppPreferences
    ) async -> RuntimeActiveModel? {
        switch purpose {
        case .transcription:
            return await dependencies.models.resolveActiveModel(
                preferences: preferences
            )
        case .voiceCleaning:
            return await dependencies.models.resolveActiveVoiceCleaningModel(
                preferences: preferences
            )
        }
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
            activeSessionPreferences = nil
            activeSegmentContext = nil
            currentSegment = nil
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
        activeSessionPreferences = nil
        activeSegmentContext = nil
        currentSegment = nil
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
        guard pendingPurposeRuntimeTransactions == 0,
              !modelTransactionInProgress,
              !hasActiveDictationWork else {
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
        activeSessionPreferences = nil
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
        guard !revokedArtifactIDs.contains(activeModel.id) else {
            activeSessionID = nil
            activationTarget = nil
            resetTriggerStateMachine()
            status = .blocked(
                .readinessBlocked(
                    .activeModelRevoked(modelID: activeModel.id)
                )
            )
            return
        }
        let voiceCleaningModel =
            await admittedVoiceCleaningModel(preferences: preferences)
        guard !revokedArtifactIDs.contains(activeModel.id) else {
            activeSessionID = nil
            activationTarget = nil
            resetTriggerStateMachine()
            status = .blocked(
                .readinessBlocked(
                    .activeModelRevoked(modelID: activeModel.id)
                )
            )
            return
        }
        let admittedVoiceCleaningModel: RuntimeActiveModel?
        if let voiceCleaningModel,
           revokedArtifactIDs.contains(voiceCleaningModel.id) {
            voiceCleaningStatus = .warning(
                modelID: voiceCleaningModel.id,
                reason: .revoked
            )
            admittedVoiceCleaningModel = nil
        } else {
            admittedVoiceCleaningModel = voiceCleaningModel
        }
        activeSessionPreferences = (
            sessionID: sessionID,
            preferences: preferences
        )
        activeSegmentContext = (
            sessionID: sessionID,
            transcriptionModel: activeModel,
            voiceCleaningModel: admittedVoiceCleaningModel
        )
        currentSegment = RuntimeCurrentSegment(
            transcriptionArtifactID: activeModel.id,
            voiceCleaningArtifactID: admittedVoiceCleaningModel?.id
        )

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
                },
                onRecordingError: { [weak self] error in
                    Task { @MainActor in
                        await self?.handleRecordingError(
                            error,
                            sessionID: sessionID
                        )
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
            activeSessionPreferences = nil
            activeSegmentContext = nil
            currentSegment = nil
            activationTarget = nil
            resetTriggerStateMachine()
            status = Self.status(forAudioStartError: error)
        }
    }

    private func handleRecordingError(
        _ error: LiveAudioRecorderError,
        sessionID: UUID
    ) async {
        guard activeSessionID == sessionID else {
            return
        }
        switch status {
        case .waitingForActivation, .recording:
            break
        case .idle, .processing, .inserting, .completed, .cancelled,
             .failed, .blocked:
            return
        }

        activationTimerToken = nil
        targetCaptureToken = nil
        activationTarget = nil
        activeSessionID = nil
        activeSessionPreferences = nil
        activeSegmentContext = nil
        currentSegment = nil
        resetTriggerStateMachine()
        status = Self.status(forAudioFinishError: error)
        await dependencies.audio.discardRecording()
    }

    private func finishRecording() async {
        guard let sessionID = activeSessionID else {
            status = .idle
            return
        }
        guard case .recording = status else {
            return
        }
        if modelTransactionInProgress {
            await waitForModelTransaction()
            guard activeSessionID == sessionID,
                  case .recording = status
            else {
                return
            }
        }
        guard let sessionPreferences = activeSessionPreferences,
              sessionPreferences.sessionID == sessionID,
              let segmentContext = activeSegmentContext,
              segmentContext.sessionID == sessionID
        else {
            activeSessionID = nil
            activeSegmentContext = nil
            currentSegment = nil
            activationTarget = nil
            status = .failed(.transcriptionFailed)
            return
        }
        defer {
            if activeSessionPreferences?.sessionID == sessionID {
                activeSessionPreferences = nil
            }
            if activeSegmentContext?.sessionID == sessionID {
                activeSegmentContext = nil
                currentSegment = nil
            }
        }
        let preferences = sessionPreferences.preferences

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

            let activeModel = segmentContext.transcriptionModel

            do {
                try await dependencies.transcriber.prepare(model: activeModel)
            } catch {
                await logRuntimeFailure(
                    error,
                    model: activeModel,
                    stage: "model_prepare"
                )
                throw error
            }
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
                model: segmentContext.voiceCleaningModel
            )
            let inferenceStartedAt = dependencies.clock.nowMilliseconds()
            let result: TranscriptionResult
            do {
                result = try await dependencies.transcriber.transcribe(preparedAudio)
            } catch {
                await logRuntimeFailure(
                    error,
                    model: activeModel,
                    stage: "inference"
                )
                throw error
            }
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
        guard !revokedArtifactIDs.contains(model.id) else {
            await dependencies.voiceCleaner.unload()
            voiceCleaningStatus = .warning(
                modelID: model.id,
                reason: .revoked
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
        model: RuntimeActiveModel?
    ) async -> TranscriptionAudioBuffer {
        guard let model else {
            if case .warning(_, reason: .revoked) = voiceCleaningStatus {
                return audio
            }
            if voiceCleaningStatus != .disabled {
                await dependencies.voiceCleaner.unload()
                voiceCleaningStatus = .disabled
            }
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

    private func admittedVoiceCleaningModel(
        preferences: AppPreferences
    ) async -> RuntimeActiveModel? {
        guard let selectedModelID =
                preferences.activeVoiceCleaningModelID
        else {
            return nil
        }
        guard !revokedArtifactIDs.contains(selectedModelID) else {
            await dependencies.voiceCleaner.unload()
            voiceCleaningStatus = .warning(
                modelID: selectedModelID,
                reason: .revoked
            )
            return nil
        }
        guard let model =
                await dependencies.models.resolveActiveVoiceCleaningModel(
                    preferences: preferences
                ),
              case .ready = await dependencies.models.readiness(for: model)
        else {
            return nil
        }
        guard !revokedArtifactIDs.contains(model.id) else {
            await dependencies.voiceCleaner.unload()
            voiceCleaningStatus = .warning(
                modelID: model.id,
                reason: .revoked
            )
            return nil
        }
        return model
    }

    private func logRuntimeFailure(
        _ error: Error,
        model: RuntimeActiveModel,
        stage: String
    ) async {
        await dependencies.diagnostics.log(
            .runtimeFailure(
                modelID: model.id,
                engine: model.engine.rawValue,
                accelerator: model.accelerator.rawValue,
                stage: stage,
                reasonCode: RuntimeFailureClassifier.code(for: error).rawValue
            )
        )
    }

    private var canStartActivation: Bool {
        targetCaptureToken == nil
            && !modelTransactionInProgress
            && pendingPurposeRuntimeTransactions == 0
            && !hasActiveDictationWork
            && status != .waitingForActivation
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

    private func waitForModelTransaction() async {
        while modelTransactionInProgress {
            await withCheckedContinuation { continuation in
                modelTransactionWaiters.append(continuation)
            }
        }
    }

    private func reservePurposeRuntimeBoundary() async {
        guard purposeRuntimeBoundaryReserved else {
            purposeRuntimeBoundaryReserved = true
            return
        }
        await withCheckedContinuation { continuation in
            purposeRuntimeBoundaryWaiters.append(continuation)
        }
    }

    private func releasePurposeRuntimeBoundary() {
        guard !purposeRuntimeBoundaryWaiters.isEmpty else {
            purposeRuntimeBoundaryReserved = false
            return
        }
        let next = purposeRuntimeBoundaryWaiters.removeFirst()
        next.resume()
    }

    private func finishModelTransaction() {
        modelTransactionInProgress = false
        let waiters = modelTransactionWaiters
        modelTransactionWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func waitForCurrentSegmentToRelease(
        _ artifactID: String
    ) async {
        while currentSegment?.owns(artifactID: artifactID) == true {
            await withCheckedContinuation { continuation in
                currentSegmentWaiters.append(
                    CurrentSegmentWaiter(
                        artifactID: artifactID,
                        continuation: continuation
                    )
                )
            }
        }
    }

    private func resumeCurrentSegmentWaiters() {
        guard !currentSegmentWaiters.isEmpty else {
            return
        }
        var retained: [CurrentSegmentWaiter] = []
        for waiter in currentSegmentWaiters {
            if currentSegment?.owns(artifactID: waiter.artifactID) == true {
                retained.append(waiter)
            } else {
                waiter.continuation.resume()
            }
        }
        currentSegmentWaiters = retained
    }

    private func effectiveModelReadiness(
        activeModel: RuntimeActiveModel?,
        installedReadiness: RuntimeModelReadiness
    ) async -> RuntimeModelReadiness {
        guard let activeModel else {
            return .noActiveModel
        }
        guard !revokedArtifactIDs.contains(activeModel.id) else {
            return .revoked(modelID: activeModel.id)
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
        case .noActiveModel, .missing, .revoked:
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
             .selectedInputUnavailable,
             .alreadyRecording,
             .notRecording,
             .inputNodeUnavailable,
             .engineStartFailed:
            return .failed(.audioFinishFailed)
        }
    }

    private static func status(forAudioStartError error: Error) -> DictationRuntimeStatus {
        guard let audioError = error as? LiveAudioRecorderError,
              audioError == .selectedInputUnavailable
        else {
            return .failed(.audioStartFailed)
        }
        return .failed(.selectedMicrophoneUnavailable)
    }
}

private struct CurrentSegmentWaiter {
    let artifactID: String
    let continuation: CheckedContinuation<Void, Never>
}
