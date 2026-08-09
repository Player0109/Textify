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
    private struct ModelSelectionKey: Equatable {
        let transcriptionLanguage: TranscriptionLanguage
        let modelSelectionScope: ModelSelectionScope
        let activeModelID: String?
        let activeVoiceCleaningModelID: String?
        let artifactOverrides: [String: String]

        init(preferences: AppPreferences) {
            transcriptionLanguage = preferences.transcriptionLanguage
            modelSelectionScope = preferences.modelSelectionScope
            activeModelID = preferences.activeModelID
            activeVoiceCleaningModelID =
                preferences.activeVoiceCleaningModelID
            artifactOverrides =
                preferences.modelArtifactOverridesByPurposeCheckpoint
        }
    }

    private struct PreparedAdmission {
        var preferences: AppPreferences
        let selectionKey: ModelSelectionKey
        let transcriptionModel: RuntimeActiveModel?
        let transcriptionStorageReadiness: RuntimeModelReadiness
        let voiceCleaningModel: RuntimeActiveModel?
    }

    private enum CapturePhase: Equatable {
        case admitting(sessionID: UUID, activated: Bool)
        case startingAudio(
            sessionID: UUID,
            activated: Bool,
            finishWhenStarted: Bool
        )
        case capturing(sessionID: UUID, activated: Bool)
        case finishing(sessionID: UUID)

        var sessionID: UUID {
            switch self {
            case let .admitting(sessionID, _),
                 let .startingAudio(sessionID, _, _),
                 let .capturing(sessionID, _),
                 let .finishing(sessionID):
                sessionID
            }
        }

        var isActivated: Bool {
            switch self {
            case let .admitting(_, activated),
                 let .startingAudio(_, activated, _),
                 let .capturing(_, activated):
                activated
            case .finishing:
                true
            }
        }
    }

    private final class CaptureTimingMilestone: @unchecked Sendable {
        private let lock = NSLock()
        private var storedValue: Int?

        func recordOnce(_ value: Int) {
            lock.lock()
            defer { lock.unlock() }
            guard storedValue == nil else {
                return
            }
            storedValue = value
        }

        func value() -> Int? {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
    }

    private struct CaptureTiming {
        let sessionID: UUID
        let triggerReceivedAtMs: Int
        var captureRequestedAtMs: Int?
        let captureStartedAtMs = CaptureTimingMilestone()
        let firstAudioAtMs = CaptureTimingMilestone()
        var triggerReleasedAtMs: Int?
        var shortcutGuardSpeechDetected = false
    }

    public private(set) var status: DictationRuntimeStatus
    public private(set) var sessionProgress: DictationSessionProgress
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
    private var capturePhase: CapturePhase?
    private var pendingAudioStartSessionID: UUID?
    private var captureTiming: CaptureTiming?
    private var latestPreferences: AppPreferences?
    private var preparedAdmission: PreparedAdmission?
    private var activeSessionPreferences:
        (sessionID: UUID, preferences: AppPreferences)?
    private var activeSegmentContext: (
        sessionID: UUID,
        transcriptionModel: RuntimeActiveModel,
        voiceCleaningModel: RuntimeActiveModel?
    )?
    private var processingSessionID: UUID?
    private var insertionSessionID: UUID?
    private var sessionEndReason = DictationSessionEndReason.triggerReleased
    private var suppressesNextTriggerRelease = false
    private var revokedArtifactIDs: Set<String> = []
    private var modelTransactionInProgress = false
    private var pendingPurposeRuntimeTransactions = 0
    private var purposeRuntimeBoundaryReserved = false
    private var purposeRuntimeBoundaryWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var modelTransactionWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var currentSegmentWaiters: [CurrentSegmentWaiter] = []
    private var isShuttingDown = false
    private var didDiscardAudioForShutdown = false
    private var shutdownOwnedArtifactID: String?

    public init(
        dependencies: RuntimeDependencies,
        triggerStateMachine: TriggerStateMachine = TriggerStateMachine()
    ) {
        self.dependencies = dependencies
        self.triggerStateMachine = triggerStateMachine
        self.status = .idle
        self.sessionProgress = .inactive
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
        if isShuttingDown
            || modelTransactionInProgress
            || pendingPurposeRuntimeTransactions > 0
            || processingSessionID != nil {
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

    public func applyPersistedPreferences(_ preferences: AppPreferences) {
        latestPreferences = preferences
        guard var preparedAdmission else {
            return
        }
        let selectionKey = ModelSelectionKey(preferences: preferences)
        guard preparedAdmission.selectionKey == selectionKey else {
            self.preparedAdmission = nil
            return
        }
        preparedAdmission.preferences = preferences
        self.preparedAdmission = preparedAdmission
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
        guard modelTransactionInProgress, !isShuttingDown else {
            return readiness
        }
        let preferences = await dependencies.settings.loadPreferences()
        applyPersistedPreferences(preferences)
        let selectionKey = ModelSelectionKey(preferences: preferences)
        let activeModel = await dependencies.models.resolveActiveModel(preferences: preferences)
        let installedReadiness = await dependencies.models.readiness(for: activeModel)

        if let activeModel, case .ready = installedReadiness {
            if !revokedArtifactIDs.contains(activeModel.id) {
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
        }

        let voiceCleaningModel =
            await prepareVoiceCleaner(preferences: preferences)

        return await publishPreparedReadiness(
            preferences: preferences,
            selectionKey: selectionKey,
            activeModel: activeModel,
            installedReadiness: installedReadiness,
            voiceCleaningModel: voiceCleaningModel
        )
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
        guard modelTransactionInProgress, !isShuttingDown else {
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
        replaceRevokedArtifactIDs(artifactIDs)
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
        _ = await refreshReadiness(resolvesVoiceCleaningModel: false)
    }

    public func replaceRevokedArtifactIDs(
        _ artifactIDs: Set<String>
    ) {
        revokedArtifactIDs = artifactIDs
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
        await refreshReadiness(resolvesVoiceCleaningModel: true)
    }

    private func refreshReadiness(
        resolvesVoiceCleaningModel: Bool
    ) async -> ReadinessSnapshot {
        let preferences = await dependencies.settings.loadPreferences()
        applyPersistedPreferences(preferences)
        let selectionKey = ModelSelectionKey(preferences: preferences)
        let activeModel = await dependencies.models.resolveActiveModel(preferences: preferences)
        let installedReadiness = await dependencies.models.readiness(for: activeModel)
        let voiceCleaningModel: RuntimeActiveModel?
        if resolvesVoiceCleaningModel {
            voiceCleaningModel =
                await resolvePreparedVoiceCleaningModel(
                    preferences: preferences
                )
        } else if let cachedModel = preparedAdmission?.voiceCleaningModel,
                  !revokedArtifactIDs.contains(cachedModel.id) {
            voiceCleaningModel = cachedModel
        } else {
            voiceCleaningModel = nil
        }
        return await publishPreparedReadiness(
            preferences: preferences,
            selectionKey: selectionKey,
            activeModel: activeModel,
            installedReadiness: installedReadiness,
            voiceCleaningModel: voiceCleaningModel
        )
    }

    private func publishPreparedReadiness(
        preferences: AppPreferences,
        selectionKey: ModelSelectionKey,
        activeModel: RuntimeActiveModel?,
        installedReadiness: RuntimeModelReadiness,
        voiceCleaningModel: RuntimeActiveModel?
    ) async -> ReadinessSnapshot {
        let permissions = await dependencies.permissions.permissionSnapshot()
        let modelReadiness = await effectiveModelReadiness(
            activeModel: activeModel,
            installedReadiness: installedReadiness
        )
        let snapshot = ReadinessSnapshot(
            permissions: permissions,
            model: modelReadiness
        )
        guard !isShuttingDown,
              latestPreferences.map({ ModelSelectionKey(preferences: $0) })
                == selectionKey
        else {
            return snapshot
        }
        readiness = snapshot
        preparedAdmission = PreparedAdmission(
            preferences: latestPreferences ?? preferences,
            selectionKey: selectionKey,
            transcriptionModel: activeModel,
            transcriptionStorageReadiness: installedReadiness,
            voiceCleaningModel: voiceCleaningModel
        )
        return snapshot
    }

    private func resolvePreparedVoiceCleaningModel(
        preferences: AppPreferences
    ) async -> RuntimeActiveModel? {
        guard let selectedModelID =
                preferences.activeVoiceCleaningModelID,
              !revokedArtifactIDs.contains(selectedModelID),
              let model =
                await dependencies.models.resolveActiveVoiceCleaningModel(
                    preferences: preferences
                ),
              !revokedArtifactIDs.contains(model.id),
              case .ready = await dependencies.models.readiness(for: model)
        else {
            return nil
        }
        return model
    }

    @discardableResult
    public func handleTriggerEvent(_ event: TriggerEvent) async -> TriggerAction {
        guard !isShuttingDown else {
            return .none
        }
        if case let .triggerDown(timestampMs) = event {
            guard canStartActivation else {
                return .none
            }
            let action = triggerStateMachine.handle(event)
            guard case let .beginArmedCapture(delayMs) = action else {
                return .none
            }
            let beganCapture = await beginArmedCapture(
                delayMs: delayMs,
                triggerReceivedAtMs: timestampMs
            )
            return beganCapture ? action : .none
        }
        if case .triggerUp = event, suppressesNextTriggerRelease {
            suppressesNextTriggerRelease = false
            return .none
        }
        if case .triggerUp = event, excludedTriggerIsHeld {
            targetCaptureToken = nil
            activationTarget = nil
            excludedTriggerIsHeld = false
            status = .idle
            return .none
        }

        let action = triggerStateMachine.handle(event)
        if action == .finishRecording,
           capturePhase?.isActivated == false {
            activateArmedCapture()
        }
        switch event {
        case let .triggerUp(timestampMs):
            if captureTiming?.sessionID == activeSessionID {
                captureTiming?.triggerReleasedAtMs = timestampMs
            }
        case .speechDetected:
            if captureTiming?.sessionID == activeSessionID {
                captureTiming?.shortcutGuardSpeechDetected = true
            }
            if activeSessionID != nil,
               case .recording = status {
                status = .recording(speechDetected: true)
            }
        case .triggerDown, .timerFired, .nonTriggerKeyDown,
             .escapeKeyDown:
            break
        }
        await handleTriggerAction(action)
        return action
    }

    public func handleTriggerAction(_ action: TriggerAction) async {
        guard !isShuttingDown else {
            return
        }
        switch action {
        case .none:
            return
        case let .beginArmedCapture(delayMs):
            _ = await beginArmedCapture(
                delayMs: delayMs,
                triggerReceivedAtMs: dependencies.clock.nowMilliseconds()
            )
        case .activateRecording:
            activateArmedCapture()
        case .beginRecording:
            await beginRecording()
        case .cancelAsShortcut:
            await cancelActiveSession(reason: .shortcutUseBeforeSpeech)
        case .cancelRecording:
            await cancelActiveSession(reason: .escapeKey)
        case .discardRecording:
            await discardArmedCapture()
        case .finishRecording:
            await finishRecording()
        }
    }

    public func cancelActiveSession(reason: DictationCancellationReason) async {
        let timing = captureTiming
        let retainsProcessingOwnership = processingSessionID != nil
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
        if !retainsProcessingOwnership {
            activeSegmentContext = nil
            currentSegment = nil
            capturePhase = nil
        }
        captureTiming = nil
        resetTriggerStateMachine()
        await dependencies.audio.discardRecording()
        sessionProgress = .inactive
        status = .cancelled(reason)
        if let timing {
            await logCaptureTiming(
                timing,
                outcome: reason == .escapeKey
                    ? "escape_discarded"
                    : "shortcut_discarded"
            )
        }
    }

    private func discardArmedCapture() async {
        guard insertionSessionID == nil else {
            return
        }
        let timing = captureTiming
        let wasActivated: Bool
        if let timing,
           let releasedAtMs = timing.triggerReleasedAtMs,
           releasedAtMs >= timing.triggerReceivedAtMs {
            wasActivated = releasedAtMs - timing.triggerReceivedAtMs
                >= triggerStateMachine.activationDelayMs
        } else {
            wasActivated = capturePhase?.isActivated == true
        }
        activationTimerToken = nil
        targetCaptureToken = nil
        activationTarget = nil
        activeSessionID = nil
        activeSessionPreferences = nil
        activeSegmentContext = nil
        currentSegment = nil
        capturePhase = nil
        captureTiming = nil
        resetTriggerStateMachine()
        await dependencies.audio.discardRecording()
        sessionProgress = .inactive
        status = .cancelled(
            wasActivated ? .noSpeechDetected : .releasedBeforeActivation
        )
        if let timing {
            await logCaptureTiming(
                timing,
                outcome: wasActivated
                    ? "empty_capture_discarded"
                    : "accidental_tap_discarded"
            )
        }
    }

    private func activateArmedCapture() {
        activationTimerToken = nil
        guard let capturePhase else {
            return
        }
        switch capturePhase {
        case let .admitting(sessionID, _):
            self.capturePhase = .admitting(
                sessionID: sessionID,
                activated: true
            )
        case let .startingAudio(
            sessionID,
            _,
            finishWhenStarted
        ):
            self.capturePhase = .startingAudio(
                sessionID: sessionID,
                activated: true,
                finishWhenStarted: finishWhenStarted
            )
        case let .capturing(sessionID, _):
            self.capturePhase = .capturing(
                sessionID: sessionID,
                activated: true
            )
            status = .recording(
                speechDetected: triggerStateMachineSpeechDetected
            )
            sessionProgress = recordingSessionProgress()
        case .finishing:
            break
        }
    }

    private var triggerStateMachineSpeechDetected: Bool {
        switch triggerStateMachine.state {
        case let .waitingForActivation(_, speechDetected),
             let .recording(speechDetected):
            speechDetected
        case .idle:
            false
        }
    }

    public func beginShutdown() {
        guard !isShuttingDown else {
            return
        }
        isShuttingDown = true
        switch status {
        case .processing, .inserting:
            shutdownOwnedArtifactID =
                currentSegment?.transcriptionArtifactID
                ?? currentSegment?.voiceCleaningArtifactID
        case .idle, .waitingForActivation, .recording, .completed,
             .cancelled, .blocked, .failed:
            shutdownOwnedArtifactID = nil
        }
        activationTimerToken = nil
        targetCaptureToken = nil
        activationTarget = nil
        excludedTriggerIsHeld = false
        activeSessionID = nil
        insertionSessionID = nil
        capturePhase = nil
        captureTiming = nil
        resetTriggerStateMachine()
        sessionProgress = .inactive
    }

    public func shutdown() async {
        beginShutdown()

        await discardAudioForShutdown()
        if shutdownOwnedArtifactID == nil {
            activeSessionPreferences = nil
            activeSegmentContext = nil
            currentSegment = nil
        }
        await performPurposeRuntimeTransaction(
            waitingForCurrentSegmentUsing: shutdownOwnedArtifactID
        ) {
            await self.dependencies.transcriber.unload()
            await self.dependencies.voiceCleaner.unload()
        }
        activeSessionPreferences = nil
        activeSegmentContext = nil
        currentSegment = nil
        shutdownOwnedArtifactID = nil
        voiceCleaningStatus = .disabled
        status = .idle
        sessionProgress = .inactive
    }

    public func discardAudioForShutdown() async {
        guard isShuttingDown, !didDiscardAudioForShutdown else {
            return
        }
        didDiscardAudioForShutdown = true
        await dependencies.audio.discardRecording()
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

    private func beginArmedCapture(
        delayMs: Int,
        triggerReceivedAtMs: Int
    ) async -> Bool {
        guard canStartActivation else {
            return false
        }
        let sessionID = UUID()
        sessionEndReason = .triggerReleased
        suppressesNextTriggerRelease = false
        sessionProgress = .inactive
        activeSessionID = sessionID
        activeSessionPreferences = nil
        activeSegmentContext = nil
        capturePhase = .admitting(
            sessionID: sessionID,
            activated: false
        )
        captureTiming = CaptureTiming(
            sessionID: sessionID,
            triggerReceivedAtMs: triggerReceivedAtMs
        )
        let nowMs = dependencies.clock.nowMilliseconds()
        let elapsedMs = nowMs >= triggerReceivedAtMs
            ? nowMs - triggerReceivedAtMs
            : 0
        startActivationTimer(delayMs: max(0, delayMs - elapsedMs))
        return await admitAndStartCapture(
            sessionID: sessionID,
            refreshPreparedAdmission: preparedAdmission == nil
        )
    }

    private func beginRecording() async {
        guard canStartActivation else {
            return
        }
        let sessionID = UUID()
        sessionEndReason = .triggerReleased
        suppressesNextTriggerRelease = false
        sessionProgress = .inactive
        activeSessionID = sessionID
        activeSessionPreferences = nil
        activeSegmentContext = nil
        capturePhase = .admitting(
            sessionID: sessionID,
            activated: true
        )
        captureTiming = nil
        _ = await refreshReadiness()
        guard isCurrentCapture(sessionID) else {
            return
        }
        _ = await admitAndStartCapture(
            sessionID: sessionID,
            refreshPreparedAdmission: false,
            validatesLiveAdmission: false
        )
    }

    private func admitAndStartCapture(
        sessionID: UUID,
        refreshPreparedAdmission: Bool,
        validatesLiveAdmission: Bool = true
    ) async -> Bool {
        let targetToken = UUID()
        targetCaptureToken = targetToken
        let capturedTarget =
            await dependencies.targetCapturer.currentTargetIdentity()
        guard isCurrentCapture(sessionID),
              targetCaptureToken == targetToken
        else {
            return false
        }
        targetCaptureToken = nil
        guard let capturedTarget else {
            failCaptureAdmission(sessionID: sessionID, status: .idle)
            return false
        }

        if refreshPreparedAdmission {
            _ = await refreshReadiness()
            guard isCurrentCapture(sessionID) else {
                return false
            }
        }
        guard let initialAdmission = preparedAdmission else {
            failCaptureAdmission(
                sessionID: sessionID,
                status: .blocked(
                    .readinessBlocked(
                        readiness.blockers.first ?? .noActiveModel
                    )
                )
            )
            return false
        }
        guard !Self.isExcluded(
            capturedTarget,
            by: initialAdmission.preferences
        ) else {
            failCaptureAdmission(
                sessionID: sessionID,
                status: .blocked(.excludedApp),
                keepsExcludedTriggerHeld: true
            )
            Task { [diagnostics = dependencies.diagnostics] in
                await diagnostics.log(.dictationBlockedExcludedApp)
            }
            return false
        }

        let liveSnapshot: ReadinessSnapshot
        if validatesLiveAdmission {
            let permissions =
                await dependencies.permissions.permissionSnapshot()
            guard isCurrentCapture(sessionID) else {
                return false
            }
            let modelReadiness = await effectiveModelReadiness(
                activeModel: initialAdmission.transcriptionModel,
                installedReadiness:
                    initialAdmission.transcriptionStorageReadiness
            )
            guard isCurrentCapture(sessionID) else {
                return false
            }
            liveSnapshot = ReadinessSnapshot(
                permissions: permissions,
                model: modelReadiness
            )
            readiness = liveSnapshot
        } else {
            liveSnapshot = readiness
        }
        guard let admission = preparedAdmission,
              admission.selectionKey == initialAdmission.selectionKey
        else {
            failCaptureAdmission(
                sessionID: sessionID,
                status: .blocked(
                    .readinessBlocked(.noActiveModel)
                )
            )
            return false
        }
        if let blocker = liveSnapshot.blockers.first {
            failCaptureAdmission(
                sessionID: sessionID,
                status: .blocked(.readinessBlocked(blocker))
            )
            return false
        }
        guard let activeModel = admission.transcriptionModel else {
            failCaptureAdmission(
                sessionID: sessionID,
                status: .blocked(.readinessBlocked(.noActiveModel))
            )
            return false
        }
        guard !Self.isExcluded(capturedTarget, by: admission.preferences)
        else {
            failCaptureAdmission(
                sessionID: sessionID,
                status: .blocked(.excludedApp),
                keepsExcludedTriggerHeld: true
            )
            Task { [diagnostics = dependencies.diagnostics] in
                await diagnostics.log(.dictationBlockedExcludedApp)
            }
            return false
        }
        guard !revokedArtifactIDs.contains(activeModel.id) else {
            failCaptureAdmission(
                sessionID: sessionID,
                status: .blocked(
                    .readinessBlocked(
                        .activeModelRevoked(modelID: activeModel.id)
                    )
                )
            )
            return false
        }

        let voiceCleaningModel: RuntimeActiveModel?
        if let preparedCleaner = admission.voiceCleaningModel,
           revokedArtifactIDs.contains(preparedCleaner.id) {
            voiceCleaningStatus = .warning(
                modelID: preparedCleaner.id,
                reason: .revoked
            )
            voiceCleaningModel = nil
        } else {
            voiceCleaningModel = admission.voiceCleaningModel
        }

        // No suspension is allowed between this final revocation check and
        // claiming Current Segment ownership for the armed capture.
        guard isCurrentCapture(sessionID) else {
            return false
        }
        guard !modelTransactionInProgress,
              pendingPurposeRuntimeTransactions == 0
        else {
            failCaptureAdmission(sessionID: sessionID, status: .idle)
            return false
        }
        guard !revokedArtifactIDs.contains(activeModel.id) else {
            failCaptureAdmission(
                sessionID: sessionID,
                status: .blocked(
                    .readinessBlocked(
                        .activeModelRevoked(modelID: activeModel.id)
                    )
                )
            )
            return false
        }
        activationTarget = capturedTarget
        activeSessionPreferences = (
            sessionID: sessionID,
            preferences: admission.preferences
        )
        activeSegmentContext = (
            sessionID: sessionID,
            transcriptionModel: activeModel,
            voiceCleaningModel: voiceCleaningModel
        )
        currentSegment = RuntimeCurrentSegment(
            transcriptionArtifactID: activeModel.id,
            voiceCleaningArtifactID: voiceCleaningModel?.id
        )
        let activated = capturePhase?.isActivated == true
        capturePhase = .startingAudio(
            sessionID: sessionID,
            activated: activated,
            finishWhenStarted: false
        )
        pendingAudioStartSessionID = sessionID
        captureTiming?.captureRequestedAtMs =
            dependencies.clock.nowMilliseconds()

        let clock = dependencies.clock
        let captureStartedAtMs = captureTiming?.captureStartedAtMs
        let firstAudioAtMs = captureTiming?.firstAudioAtMs
        do {
            try await dependencies.audio.startRecording(
                microphone: admission.preferences.microphoneSelection,
                maximumDurationSeconds:
                    DictationSessionLimits.maximumDurationSeconds,
                onCaptureStarted: {
                    captureStartedAtMs?.recordOnce(
                        clock.nowMilliseconds()
                    )
                },
                onFirstAudio: { firstSampleUptimeMilliseconds in
                    firstAudioAtMs?.recordOnce(
                        firstSampleUptimeMilliseconds
                    )
                },
                onSpeechDetected: { [weak self] in
                    Task { @MainActor in
                        guard let self,
                              self.activeSessionID == sessionID
                        else {
                            return
                        }
                        _ = await self.handleTriggerEvent(
                            .speechDetected(
                                timestampMs:
                                    self.dependencies.clock.nowMilliseconds()
                            )
                        )
                    }
                },
                onMaximumDurationReached: { [weak self] in
                    Task { @MainActor in
                        guard let self,
                              self.activeSessionID == sessionID
                        else {
                            return
                        }
                        self.sessionEndReason = .sessionLimitReached
                        if self.captureTiming != nil {
                            self.suppressesNextTriggerRelease = true
                            self.resetTriggerStateMachine()
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

            guard activeSessionID == sessionID,
                  let capturePhase,
                  case let .startingAudio(
                      phaseSessionID,
                      activated,
                      finishWhenStarted
                  ) = capturePhase,
                  phaseSessionID == sessionID
            else {
                await dependencies.audio.discardRecording()
                clearPendingAudioStart(sessionID: sessionID)
                return false
            }
            clearPendingAudioStart(sessionID: sessionID)
            self.capturePhase = .capturing(
                sessionID: sessionID,
                activated: activated
            )
            if activated {
                status = .recording(
                    speechDetected: triggerStateMachineSpeechDetected
                )
                sessionProgress = recordingSessionProgress()
            }
            if finishWhenStarted {
                await finishRecording()
            }
            return true
        } catch {
            clearPendingAudioStart(sessionID: sessionID)
            guard isCurrentCapture(sessionID) else {
                return false
            }
            let timing = captureTiming
            clearCaptureState(sessionID: sessionID)
            resetTriggerStateMachine()
            status = Self.status(forAudioStartError: error)
            if let timing {
                await logCaptureTiming(
                    timing,
                    outcome: "capture_start_failed"
                )
            }
            return false
        }
    }

    private func isCurrentCapture(_ sessionID: UUID) -> Bool {
        !isShuttingDown
            && activeSessionID == sessionID
            && capturePhase?.sessionID == sessionID
    }

    private func clearPendingAudioStart(sessionID: UUID) {
        if pendingAudioStartSessionID == sessionID {
            pendingAudioStartSessionID = nil
        }
    }

    private func failCaptureAdmission(
        sessionID: UUID,
        status: DictationRuntimeStatus,
        keepsExcludedTriggerHeld: Bool = false
    ) {
        guard isCurrentCapture(sessionID) else {
            return
        }
        activationTimerToken = nil
        targetCaptureToken = nil
        activationTarget = nil
        activeSessionID = nil
        activeSessionPreferences = nil
        activeSegmentContext = nil
        currentSegment = nil
        capturePhase = nil
        captureTiming = nil
        excludedTriggerIsHeld = keepsExcludedTriggerHeld
        resetTriggerStateMachine()
        sessionProgress = .inactive
        self.status = status
    }

    private func clearCaptureState(sessionID: UUID) {
        guard activeSessionID == sessionID else {
            return
        }
        activationTimerToken = nil
        targetCaptureToken = nil
        activationTarget = nil
        activeSessionID = nil
        activeSessionPreferences = nil
        activeSegmentContext = nil
        currentSegment = nil
        capturePhase = nil
        captureTiming = nil
        sessionProgress = .inactive
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

        let timing = captureTiming
        activationTimerToken = nil
        targetCaptureToken = nil
        activationTarget = nil
        activeSessionID = nil
        activeSessionPreferences = nil
        activeSegmentContext = nil
        currentSegment = nil
        capturePhase = nil
        captureTiming = nil
        resetTriggerStateMachine()
        sessionProgress = .inactive
        status = Self.status(forAudioFinishError: error)
        await dependencies.audio.discardRecording()
        if let timing {
            await logCaptureTiming(timing, outcome: "recording_error")
        }
    }

    private func finishRecording() async {
        guard let sessionID = activeSessionID else {
            return
        }
        if case let .startingAudio(
            phaseSessionID,
            true,
            _
        ) = capturePhase,
           phaseSessionID == sessionID {
            capturePhase = .startingAudio(
                sessionID: sessionID,
                activated: true,
                finishWhenStarted: true
            )
            activationTimerToken = nil
            return
        }
        switch status {
        case .recording:
            break
        case .waitingForActivation:
            let timing = captureTiming
            clearCaptureState(sessionID: sessionID)
            resetTriggerStateMachine()
            await dependencies.audio.discardRecording()
            status = .cancelled(.noSpeechDetected)
            if let timing {
                await logCaptureTiming(
                    timing,
                    outcome: "capture_start_failed"
                )
            }
            return
        case .idle, .processing, .inserting, .completed, .cancelled,
             .blocked, .failed:
            return
        }
        guard let capturePhase,
              capturePhase.sessionID == sessionID,
              case .capturing(_, true) = capturePhase
        else {
            let timing = self.captureTiming
            clearCaptureState(sessionID: sessionID)
            resetTriggerStateMachine()
            await dependencies.audio.discardRecording()
            status = .cancelled(.noSpeechDetected)
            if let timing {
                await logCaptureTiming(
                    timing,
                    outcome: "capture_start_failed"
                )
            }
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
            let timing = captureTiming
            clearCaptureState(sessionID: sessionID)
            resetTriggerStateMachine()
            await dependencies.audio.discardRecording()
            status = .failed(.transcriptionFailed)
            if let timing {
                await logCaptureTiming(timing, outcome: "recording_error")
            }
            return
        }
        defer {
            if activeSessionPreferences?.sessionID == sessionID {
                activeSessionPreferences = nil
            }
            if self.processingSessionID == sessionID {
                self.processingSessionID = nil
            }
            if activeSegmentContext?.sessionID == sessionID {
                activeSegmentContext = nil
                currentSegment = nil
            }
            if self.capturePhase?.sessionID == sessionID {
                self.capturePhase = nil
            }
            if self.captureTiming?.sessionID == sessionID {
                self.captureTiming = nil
            }
        }
        let preferences = sessionPreferences.preferences

        activationTimerToken = nil
        self.capturePhase = .finishing(sessionID: sessionID)
        processingSessionID = sessionID
        status = .processing
        sessionProgress = .processing(
            completedWindows: 0,
            totalWindows: 0,
            endReason: sessionEndReason
        )

        do {
            let capturedAudio = try await dependencies.audio.finishRecording()
            guard activeSessionID == sessionID else {
                return
            }
            let audio = EdgeSilenceTrimmer().trim(capturedAudio)
            guard !audio.isEmpty else {
                if let timing = captureTiming {
                    captureTiming = nil
                    await logCaptureTiming(
                        timing,
                        outcome: "empty_capture_discarded"
                    )
                }
                activeSessionID = nil
                activationTarget = nil
                sessionProgress = .inactive
                status = .cancelled(.noSpeechDetected)
                return
            }

            if let timing = captureTiming {
                captureTiming = nil
                await logCaptureTiming(
                    timing,
                    outcome: "submitted_to_asr"
                )
            }

            let activeModel = segmentContext.transcriptionModel
            let processor = RuntimeDictationSessionProcessor(
                transcriber: dependencies.transcriber,
                voiceCleaner: dependencies.voiceCleaner,
                clock: dependencies.clock
            )
            let sessionOutcome: RuntimeDictationSessionOutcome
            do {
                sessionOutcome = try await processor.process(
                    audio: audio,
                    transcriptionModel: activeModel,
                    voiceCleaningModel: segmentContext.voiceCleaningModel,
                    progress: { [weak self] completedWindows, totalWindows in
                        await self?.updateSessionProgress(
                            sessionID: sessionID,
                            completedWindows: completedWindows,
                            totalWindows: totalWindows
                        )
                    },
                    shouldContinue: { [weak self] in
                        guard let self else {
                            return false
                        }
                        return await self.processingMayContinue(
                            sessionID: sessionID
                        )
                    }
                )
            } catch let error as RuntimeDictationSessionError {
                let stage: String
                switch error.stage {
                case .transcriberPreparation:
                    stage = "model_prepare"
                case .transcription:
                    stage = "inference"
                }
                await logRuntimeFailure(
                    error.underlyingError,
                    model: activeModel,
                    stage: stage
                )
                throw error.underlyingError
            }
            guard activeSessionID == sessionID else {
                return
            }

            let completion: RuntimeDictationSessionCompletion
            switch sessionOutcome {
            case let .discarded(discard):
                await applyVoiceCleaningSummary(discard.voiceCleaning)
                guard activeSessionID == sessionID else {
                    return
                }
                await dependencies.diagnostics.log(
                    .transcriptionDiscarded(
                        modelID: activeModel.id,
                        noSpeechProbability:
                            discard.rejectedWindow.noSpeechProbability,
                        averageLogProbability:
                            discard.rejectedWindow.averageLogProbability,
                        compressionRatio:
                            discard.rejectedWindow.compressionRatio
                    )
                )
                guard activeSessionID == sessionID else {
                    return
                }
                activeSessionID = nil
                activationTarget = nil
                sessionProgress = .inactive
                status = .idle
                return
            case let .completed(value):
                completion = value
            }
            await applyVoiceCleaningSummary(completion.voiceCleaning)
            guard activeSessionID == sessionID else {
                return
            }
            await dependencies.diagnostics.log(
                .transcriptionCompleted(
                    modelID: activeModel.id,
                    engine: activeModel.engine.rawValue,
                    accelerator: activeModel.accelerator.rawValue,
                    backendReadiness: "ready",
                    audioDurationMs: max(0, Int(audio.durationSeconds * 1_000)),
                    inferenceDurationMs: completion.inferenceDurationMs,
                    textLengthBucket:
                        Self.textLengthBucket(for: completion.text.count),
                    windowCount: completion.windowCount,
                    terminationReason: sessionEndReason.rawValue
                )
            )
            guard activeSessionID == sessionID else {
                return
            }

            let processed = await dependencies.postProcessor
                .process(rawText: completion.text, preferences: preferences)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard activeSessionID == sessionID else {
                return
            }
            guard !processed.isEmpty else {
                activeSessionID = nil
                activationTarget = nil
                sessionProgress = .inactive
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
            sessionProgress = .inactive
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
        } catch RuntimeDictationSessionInterruption.cancelled {
            guard activeSessionID == sessionID else {
                return
            }
            activeSessionID = nil
            insertionSessionID = nil
            activationTarget = nil
            sessionProgress = .inactive
            if !isShuttingDown {
                status = .idle
            }
        } catch let error as LiveAudioRecorderError {
            guard activeSessionID == sessionID else {
                return
            }
            if let timing = captureTiming {
                captureTiming = nil
                await logCaptureTiming(
                    timing,
                    outcome: error == .emptyRecording
                        ? "empty_capture_discarded"
                        : "recording_error"
                )
            }
            activeSessionID = nil
            insertionSessionID = nil
            activationTarget = nil
            sessionProgress = .inactive
            status = Self.status(forAudioFinishError: error)
        } catch is WhisperRuntimeError {
            guard activeSessionID == sessionID else {
                return
            }
            activeSessionID = nil
            insertionSessionID = nil
            activationTarget = nil
            sessionProgress = .inactive
            status = .failed(.transcriptionFailed)
        } catch {
            guard activeSessionID == sessionID else {
                return
            }
            activeSessionID = nil
            insertionSessionID = nil
            activationTarget = nil
            sessionProgress = .inactive
            status = .failed(.transcriptionFailed)
        }
    }

    private func prepareVoiceCleaner(
        preferences: AppPreferences
    ) async -> RuntimeActiveModel? {
        guard let selectedModelID = preferences.activeVoiceCleaningModelID else {
            await dependencies.voiceCleaner.unload()
            voiceCleaningStatus = .disabled
            return nil
        }
        guard let model = await dependencies.models.resolveActiveVoiceCleaningModel(
            preferences: preferences
        ), case .ready = await dependencies.models.readiness(for: model) else {
            await dependencies.voiceCleaner.unload()
            voiceCleaningStatus = .warning(
                modelID: selectedModelID,
                reason: .modelUnavailable
            )
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
        return model
    }

    private func applyVoiceCleaningSummary(
        _ summary: RuntimeDictationSessionVoiceCleaningSummary
    ) async {
        guard let modelID = summary.modelID else {
            if case .warning(_, reason: .revoked) = voiceCleaningStatus {
                return
            }
            if voiceCleaningStatus != .disabled {
                await dependencies.voiceCleaner.unload()
                voiceCleaningStatus = .disabled
            }
            return
        }

        let result: String
        if summary.usedRawFallback {
            voiceCleaningStatus = .warning(
                modelID: modelID,
                reason: .processingFailed
            )
            result = "raw_audio_fallback"
        } else {
            voiceCleaningStatus = .ready(modelID: modelID)
            result = "cleaned"
        }
        await dependencies.diagnostics.log(
            .voiceCleaning(
                modelID: modelID,
                durationMs: summary.durationMs,
                result: result
            )
        )
    }

    private func updateSessionProgress(
        sessionID: UUID,
        completedWindows: Int,
        totalWindows: Int
    ) {
        guard activeSessionID == sessionID,
              case .processing = status
        else {
            return
        }
        sessionProgress = .processing(
            completedWindows: max(0, completedWindows),
            totalWindows: max(0, totalWindows),
            endReason: sessionEndReason
        )
    }

    private func processingMayContinue(sessionID: UUID) -> Bool {
        !isShuttingDown
            && processingSessionID == sessionID
            && activeSessionID == sessionID
    }

    private func recordingSessionProgress() -> DictationSessionProgress {
        let startedAtMilliseconds =
            captureTiming?.captureStartedAtMs.value()
            ?? dependencies.clock.nowMilliseconds()
        let maximumDurationMilliseconds = Int(
            DictationSessionLimits.maximumDurationSeconds * 1_000
        )
        return .recording(
            deadlineUptimeMilliseconds:
                startedAtMilliseconds + maximumDurationMilliseconds
        )
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

    private func logCaptureTiming(
        _ timing: CaptureTiming,
        outcome: String
    ) async {
        func duration(from timestampMs: Int?) -> Int? {
            timestampMs.map {
                max(0, $0 - timing.triggerReceivedAtMs)
            }
        }

        await dependencies.diagnostics.log(
            .dictationCaptureTiming(
                triggerToCaptureRequestMs: duration(
                    from: timing.captureRequestedAtMs
                ),
                triggerToCaptureStartMs: duration(
                    from: timing.captureStartedAtMs.value()
                ),
                triggerToFirstAudioMs: duration(
                    from: timing.firstAudioAtMs.value()
                ),
                triggerHoldDurationMs: duration(
                    from: timing.triggerReleasedAtMs
                ),
                shortcutGuardSpeechDetected:
                    timing.shortcutGuardSpeechDetected,
                preASROutcome: outcome
            )
        )
    }

    private var canStartActivation: Bool {
        !isShuttingDown
            && targetCaptureToken == nil
            && pendingAudioStartSessionID == nil
            && !modelTransactionInProgress
            && pendingPurposeRuntimeTransactions == 0
            && processingSessionID == nil
            && !hasActiveDictationWork
            && status != .waitingForActivation
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
        if activeSessionID != nil
            || processingSessionID != nil
            || insertionSessionID != nil {
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
