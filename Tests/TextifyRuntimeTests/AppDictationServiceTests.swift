import Foundation
import TextifyAudio
import TextifyDiagnostics
import TextifyHotkeys
import TextifyInsertion
import TextifyModels
import TextifySettings
import TextifyTranscription
@testable import TextifyRuntime
import XCTest

@MainActor
final class AppDictationServiceTests: XCTestCase {
    func testPreparingCandidateTranscriptionModelDoesNotMutateStoredSelection() async {
        var storedPreferences = AppPreferences.defaults
        storedPreferences.activeModelID = "previous-model"
        let fakes = RuntimeFakes.ready(preferences: storedPreferences)
        let service = AppDictationService(dependencies: fakes.dependencies)
        var candidatePreferences = storedPreferences
        candidatePreferences.activeModelID = RuntimeActiveModel.fixture.id

        let result = await service.prepareModelSelection(
            modelID: RuntimeActiveModel.fixture.id,
            purpose: .transcription,
            preferences: candidatePreferences
        )
        let persistedModelID = await fakes.settings.loadPreferences().activeModelID
        let prepareCount = await fakes.transcriber.prepareCount()

        XCTAssertEqual(
            result,
            .ready(modelID: RuntimeActiveModel.fixture.id)
        )
        XCTAssertEqual(persistedModelID, "previous-model")
        XCTAssertEqual(prepareCount, 1)
    }

    func testPreparingUnavailableCandidateReportsNeedsRepairWithoutLoadingRuntime() async {
        let fakes = RuntimeFakes.blocked(
            blocker: .activeModelMissing(modelID: RuntimeActiveModel.fixture.id)
        )
        let service = AppDictationService(dependencies: fakes.dependencies)
        var candidatePreferences = AppPreferences.defaults
        candidatePreferences.activeModelID = RuntimeActiveModel.fixture.id

        let result = await service.prepareModelSelection(
            modelID: RuntimeActiveModel.fixture.id,
            purpose: .transcription,
            preferences: candidatePreferences
        )
        let prepareCount = await fakes.transcriber.prepareCount()

        XCTAssertEqual(
            result,
            .needsRepair(
                modelID: RuntimeActiveModel.fixture.id,
                readiness: .missing(modelID: RuntimeActiveModel.fixture.id)
            )
        )
        XCTAssertEqual(prepareCount, 0)
    }

    func testCandidateReadinessUsesResolverWithoutPreparingOrPersisting() async {
        let modelID = RuntimeActiveModel.fixture.id
        let fakes = RuntimeFakes.blocked(
            blocker: .transcriptionRuntimeFailed(modelID: modelID)
        )
        let service = AppDictationService(dependencies: fakes.dependencies)
        var candidatePreferences = AppPreferences.defaults
        candidatePreferences.activeModelID = modelID

        let readiness = await service.modelReadiness(
            modelID: modelID,
            purpose: .transcription,
            preferences: candidatePreferences
        )
        let prepareCount = await fakes.transcriber.prepareCount()
        let persistedModelID = await fakes.settings.loadPreferences()
            .activeModelID

        XCTAssertEqual(
            readiness,
            .failed(modelID: modelID, reason: .loadFailed)
        )
        XCTAssertEqual(prepareCount, 0)
        XCTAssertEqual(persistedModelID, AppPreferences.defaults.activeModelID)
    }

    func testUseDuringRecordingAppliesToTheNextSegment() async {
        var initialPreferences = AppPreferences.defaults
        initialPreferences.activeModelID = RuntimeActiveModel.fixture.id
        let fakes = RuntimeFakes.ready(preferences: initialPreferences)
        let candidate = RuntimeActiveModel.alternateFixture
        await fakes.models.setSelectableModels([
            .fixture,
            candidate,
        ])
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        var futurePreferences = initialPreferences
        futurePreferences.activeModelID = candidate.id
        let preparation = await service.prepareModelSelection(
            modelID: candidate.id,
            purpose: .transcription,
            preferences: futurePreferences
        )
        await fakes.settings.savePreferences(futurePreferences)
        await service.handleTriggerAction(.finishRecording)
        let preparedModelIDs = await fakes.transcriber.preparedModelIDs()

        XCTAssertEqual(preparation, .ready(modelID: candidate.id))
        XCTAssertEqual(
            preparedModelIDs,
            [candidate.id, RuntimeActiveModel.fixture.id]
        )
        XCTAssertEqual(
            service.status,
            .completed(textLengthBucket: "1-50")
        )
    }

    func testEnableDuringRecordingAppliesToTheNextSegment() async {
        let initialPreferences = AppPreferences.defaults
        let fakes = RuntimeFakes.ready(preferences: initialPreferences)
        let cleaner = RuntimeActiveModel.voiceCleanerFixture
        await fakes.models.setSelectableVoiceCleaningModels([cleaner])
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        var futurePreferences = initialPreferences
        futurePreferences.activeVoiceCleaningModelID = cleaner.id
        let preparation = await service.prepareModelSelection(
            modelID: cleaner.id,
            purpose: .voiceCleaning,
            preferences: futurePreferences
        )
        await fakes.settings.savePreferences(futurePreferences)
        await service.handleTriggerAction(.finishRecording)
        let cleanCount = await fakes.voiceCleaner.cleanCallCount()

        XCTAssertEqual(preparation, .ready(modelID: cleaner.id))
        XCTAssertEqual(cleanCount, 0)
    }

    func testDisableDuringRecordingAppliesToTheNextSegment() async {
        var initialPreferences = AppPreferences.defaults
        let cleaner = RuntimeActiveModel.voiceCleanerFixture
        initialPreferences.activeVoiceCleaningModelID = cleaner.id
        let fakes = RuntimeFakes.ready(preferences: initialPreferences)
        await fakes.models.setSelectableVoiceCleaningModels([cleaner])
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        var futurePreferences = initialPreferences
        futurePreferences.activeVoiceCleaningModelID = nil
        await fakes.settings.savePreferences(futurePreferences)
        _ = await service.prepareActiveModelIfAvailable()
        await service.handleTriggerAction(.finishRecording)
        let preparedModelIDs = await fakes.voiceCleaner.preparedModelIDs()
        let cleanCount = await fakes.voiceCleaner.cleanCallCount()

        XCTAssertEqual(preparedModelIDs, [cleaner.id])
        XCTAssertEqual(cleanCount, 1)
    }

    func testCurrentSegmentCapturesBothArtifactIdentitiesAndFinishesAfterRevocation() async {
        var preferences = AppPreferences.defaults
        preferences.activeModelID = RuntimeActiveModel.fixture.id
        preferences.activeVoiceCleaningModelID =
            RuntimeActiveModel.voiceCleanerFixture.id
        let fakes = RuntimeFakes.ready(preferences: preferences)
        await fakes.models.setVoiceCleaningModel(.voiceCleanerFixture)
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)

        XCTAssertEqual(
            service.currentSegment,
            RuntimeCurrentSegment(
                transcriptionArtifactID: RuntimeActiveModel.fixture.id,
                voiceCleaningArtifactID:
                    RuntimeActiveModel.voiceCleanerFixture.id
            )
        )

        await service.updateRevokedArtifactIDs([
            RuntimeActiveModel.fixture.id,
            RuntimeActiveModel.voiceCleanerFixture.id,
        ])
        await service.handleTriggerAction(.finishRecording)

        XCTAssertEqual(
            service.status,
            .completed(textLengthBucket: "1-50")
        )
        XCTAssertNil(service.currentSegment)
        let cleanCallCount = await fakes.voiceCleaner.cleanCallCount()
        XCTAssertEqual(cleanCallCount, 1)

        await service.handleTriggerAction(.beginRecording)

        XCTAssertEqual(
            service.status,
            .blocked(
                .readinessBlocked(
                    .activeModelRevoked(
                        modelID: RuntimeActiveModel.fixture.id
                    )
                )
            )
        )
        XCTAssertNil(service.currentSegment)
        let startCount = await fakes.audio.startCount()
        XCTAssertEqual(startCount, 1)
    }

    func testPurposeRuntimeTransactionWaitsForOwnedCurrentSegment() async {
        let fakes = RuntimeFakes.ready()
        let service = AppDictationService(dependencies: fakes.dependencies)
        var crossedBoundary = false

        await service.handleTriggerAction(.beginRecording)
        let transaction = Task { @MainActor in
            await service.performPurposeRuntimeTransaction(
                waitingForCurrentSegmentUsing:
                    RuntimeActiveModel.fixture.id
            ) {
                crossedBoundary = true
            }
        }
        await settle()

        XCTAssertFalse(crossedBoundary)
        XCTAssertEqual(
            service.currentSegment?.transcriptionArtifactID,
            RuntimeActiveModel.fixture.id
        )

        await service.handleTriggerAction(.finishRecording)
        await transaction.value

        XCTAssertTrue(crossedBoundary)
        XCTAssertNil(service.currentSegment)
    }

    func testPurposeRuntimeTransactionPreventsNewSegmentAdmission() async {
        let fakes = RuntimeFakes.ready()
        let service = AppDictationService(dependencies: fakes.dependencies)
        let gate = PurposeRuntimeBoundaryGate()

        let transaction = Task { @MainActor in
            await service.performPurposeRuntimeTransaction {
                await gate.wait()
            }
        }
        await waitUntil { await gate.isWaiting() }

        await service.handleTriggerAction(.beginRecording)

        XCTAssertNil(service.currentSegment)
        XCTAssertEqual(service.status, .idle)

        await gate.release()
        await transaction.value
    }

    func testPurposeRuntimeTransactionsSerialize() async {
        let fakes = RuntimeFakes.ready()
        let service = AppDictationService(dependencies: fakes.dependencies)
        let gate = PurposeRuntimeBoundaryGate()
        var enteredSecondTransaction = false

        let first = Task { @MainActor in
            await service.performPurposeRuntimeTransaction {
                await gate.wait()
            }
        }
        await waitUntil { await gate.isWaiting() }
        let second = Task { @MainActor in
            await service.performPurposeRuntimeTransaction {
                enteredSecondTransaction = true
            }
        }
        await settle()

        XCTAssertFalse(enteredSecondTransaction)

        await gate.release()
        await first.value
        await second.value

        XCTAssertTrue(enteredSecondTransaction)
    }

    func testWaitingRemovalBoundaryCannotBeOvertakenByLaterTransaction() async {
        let fakes = RuntimeFakes.ready()
        let service = AppDictationService(dependencies: fakes.dependencies)
        var entryOrder: [String] = []

        await service.handleTriggerAction(.beginRecording)
        let removal = Task { @MainActor in
            await service.performPurposeRuntimeTransaction(
                waitingForCurrentSegmentUsing:
                    RuntimeActiveModel.fixture.id
            ) {
                entryOrder.append("removal")
            }
        }
        await settle()
        let activation = Task { @MainActor in
            await service.performPurposeRuntimeTransaction {
                entryOrder.append("activation")
            }
        }
        await settle()

        XCTAssertTrue(entryOrder.isEmpty)

        await service.handleTriggerAction(.finishRecording)
        await removal.value
        await activation.value

        XCTAssertEqual(entryOrder, ["removal", "activation"])
    }

    func testRevokedCleanerIsExcludedFromLaterSegmentWithoutBlockingTranscription() async {
        var preferences = AppPreferences.defaults
        preferences.activeModelID = RuntimeActiveModel.fixture.id
        preferences.activeVoiceCleaningModelID =
            RuntimeActiveModel.voiceCleanerFixture.id
        let fakes = RuntimeFakes.ready(preferences: preferences)
        await fakes.models.setVoiceCleaningModel(.voiceCleanerFixture)
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.updateRevokedArtifactIDs([
            RuntimeActiveModel.voiceCleanerFixture.id,
        ])
        await service.handleTriggerAction(.beginRecording)

        XCTAssertEqual(
            service.currentSegment,
            RuntimeCurrentSegment(
                transcriptionArtifactID: RuntimeActiveModel.fixture.id,
                voiceCleaningArtifactID: nil
            )
        )

        await service.handleTriggerAction(.finishRecording)

        XCTAssertEqual(
            service.status,
            .completed(textLengthBucket: "1-50")
        )
        let cleanCallCount = await fakes.voiceCleaner.cleanCallCount()
        XCTAssertEqual(cleanCallCount, 0)
        XCTAssertEqual(
            service.voiceCleaningStatus,
            .warning(
                modelID: RuntimeActiveModel.voiceCleanerFixture.id,
                reason: .revoked
            )
        )
    }

    func testTranscriberRevokedWhileCleanerResolvesCannotEnterCurrentSegment() async {
        var preferences = AppPreferences.defaults
        preferences.activeModelID = RuntimeActiveModel.fixture.id
        preferences.activeVoiceCleaningModelID =
            RuntimeActiveModel.voiceCleanerFixture.id
        let fakes = RuntimeFakes.ready(preferences: preferences)
        await fakes.models.setVoiceCleaningModel(.voiceCleanerFixture)
        await fakes.models.setSuspendVoiceCleaningResolution(true)
        let service = AppDictationService(dependencies: fakes.dependencies)

        let admission = Task {
            await service.handleTriggerAction(.beginRecording)
        }
        await waitUntil {
            await fakes.models.isVoiceCleaningResolutionSuspended()
        }
        await service.updateRevokedArtifactIDs([
            RuntimeActiveModel.fixture.id,
        ])
        await fakes.models.releaseVoiceCleaningResolution()
        await admission.value

        XCTAssertEqual(
            service.status,
            .blocked(
                .readinessBlocked(
                    .activeModelRevoked(
                        modelID: RuntimeActiveModel.fixture.id
                    )
                )
            )
        )
        XCTAssertNil(service.currentSegment)
        let startCount = await fakes.audio.startCount()
        XCTAssertEqual(startCount, 0)
    }

    func testCandidatePreparationCannotCrossRevocationIntoActivation() async {
        let fakes = RuntimeFakes.ready()
        let candidate = RuntimeActiveModel.alternateFixture
        await fakes.models.setSelectableModels([candidate])
        await fakes.transcriber.setSuspendPrepareUntilReleased(true)
        let service = AppDictationService(dependencies: fakes.dependencies)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = candidate.id

        let task = Task {
            await service.prepareModelSelection(
                modelID: candidate.id,
                purpose: .transcription,
                preferences: preferences
            )
        }
        await waitUntil { await fakes.transcriber.isPrepareSuspended() }
        await service.updateRevokedArtifactIDs([candidate.id])
        await fakes.transcriber.setSuspendPrepareUntilReleased(false)
        await fakes.transcriber.releasePrepare()

        let result = await task.value
        XCTAssertEqual(
            result,
            .revoked(modelID: candidate.id)
        )
    }

    func testModelTransactionsDoNotTouchSharedBackendsDuringProcessing() async {
        let fakes = RuntimeFakes.ready()
        let candidate = RuntimeActiveModel.alternateFixture
        await fakes.models.setSelectableModels([
            .fixture,
            candidate,
        ])
        await fakes.transcriber.setSuspendUntilReleased(true)
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        let finishTask = Task {
            await service.handleTriggerAction(.finishRecording)
        }
        await waitUntil { await fakes.transcriber.isSuspended() }
        var futurePreferences = AppPreferences.defaults
        futurePreferences.activeModelID = candidate.id

        let preparation = await service.prepareModelSelection(
            modelID: candidate.id,
            purpose: .transcription,
            preferences: futurePreferences
        )
        _ = await service.prepareActiveModelIfAvailable()
        let preparedModelIDs = await fakes.transcriber.preparedModelIDs()

        XCTAssertFalse(service.allowsModelTransactions)
        XCTAssertEqual(preparation, .busy(modelID: candidate.id))
        XCTAssertEqual(
            preparedModelIDs,
            [RuntimeActiveModel.fixture.id]
        )

        await fakes.transcriber.release()
        await finishTask.value
        XCTAssertTrue(service.allowsModelTransactions)
    }

    func testRecordingCompletionWaitsForInFlightModelTransaction() async {
        let fakes = RuntimeFakes.ready()
        let candidate = RuntimeActiveModel.alternateFixture
        await fakes.models.setSelectableModels([
            .fixture,
            candidate,
        ])
        await fakes.transcriber.setSuspendPrepareUntilReleased(true)
        let service = AppDictationService(dependencies: fakes.dependencies)
        var futurePreferences = AppPreferences.defaults
        futurePreferences.activeModelID = candidate.id

        await service.handleTriggerAction(.beginRecording)
        let activationTask = Task {
            await service.prepareModelSelection(
                modelID: candidate.id,
                purpose: .transcription,
                preferences: futurePreferences
            )
        }
        await waitUntil { await fakes.transcriber.isPrepareSuspended() }
        let finishTask = Task {
            await service.handleTriggerAction(.finishRecording)
        }
        await settle()

        let finishCountBeforeActivation = await fakes.audio.finishCount()
        XCTAssertEqual(service.status, .recording(speechDetected: false))
        XCTAssertEqual(finishCountBeforeActivation, 0)

        await fakes.transcriber.setSuspendPrepareUntilReleased(false)
        await fakes.transcriber.releasePrepare()
        let preparation = await activationTask.value
        await finishTask.value
        let preparedModelIDs = await fakes.transcriber.preparedModelIDs()

        XCTAssertEqual(preparation, .ready(modelID: candidate.id))
        XCTAssertEqual(
            preparedModelIDs,
            [candidate.id, RuntimeActiveModel.fixture.id]
        )
        XCTAssertEqual(
            service.status,
            .completed(textLengthBucket: "1-50")
        )
    }

    func testPreparingVoiceCleanerReportsFailureWithoutChangingStoredSelection() async {
        var storedPreferences = AppPreferences.defaults
        storedPreferences.activeVoiceCleaningModelID = "previous-cleaner"
        let fakes = RuntimeFakes.ready(preferences: storedPreferences)
        let candidate = RuntimeActiveModel.voiceCleanerFixture
        await fakes.models.setVoiceCleaningModel(candidate)
        await fakes.voiceCleaner.setPrepareError(FakeVoiceCleaningError.failed)
        let service = AppDictationService(dependencies: fakes.dependencies)
        var candidatePreferences = storedPreferences
        candidatePreferences.activeVoiceCleaningModelID = candidate.id

        let result = await service.prepareModelSelection(
            modelID: candidate.id,
            purpose: .voiceCleaning,
            preferences: candidatePreferences
        )
        let persistedCleanerID = await fakes.settings.loadPreferences()
            .activeVoiceCleaningModelID
        let prepareCount = await fakes.voiceCleaner.prepareCallCount()

        XCTAssertEqual(result, .failed(modelID: candidate.id))
        XCTAssertEqual(persistedCleanerID, "previous-cleaner")
        XCTAssertEqual(prepareCount, 1)
    }

    func testPrepareActiveModelLoadsInstalledModelBeforeFirstDictation() async {
        let fakes = RuntimeFakes.ready()
        let service = AppDictationService(dependencies: fakes.dependencies)

        let snapshot = await service.prepareActiveModelIfAvailable()
        let prepareCount = await fakes.transcriber.prepareCount()
        let modelLoadCount = await fakes.diagnostics.modelLoadCount()

        XCTAssertEqual(prepareCount, 1)
        XCTAssertEqual(modelLoadCount, 1)
        XCTAssertEqual(snapshot.model, .ready(modelID: RuntimeActiveModel.fixture.id))
        XCTAssertTrue(snapshot.canDictate)
    }

    func testPrepareFailureLogsClosedRuntimeReason() async {
        let fakes = RuntimeFakes.ready()
        await fakes.transcriber.setPrepareError(
            TranscribeCppRuntimeError.automaticLanguageDetectionRequired
        )
        let service = AppDictationService(dependencies: fakes.dependencies)

        _ = await service.prepareActiveModelIfAvailable()

        let failures = await fakes.diagnostics.runtimeFailures()
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.stage, "model_prepare")
        XCTAssertEqual(
            failures.first?.reasonCode,
            "automatic_language_detection_required"
        )
    }

    func testPrepareActiveModelSkipsMissingInstall() async {
        let fakes = RuntimeFakes.blocked(
            blocker: .activeModelMissing(modelID: RuntimeActiveModel.fixture.id)
        )
        let service = AppDictationService(dependencies: fakes.dependencies)

        let snapshot = await service.prepareActiveModelIfAvailable()
        let prepareCount = await fakes.transcriber.prepareCount()
        let modelLoadCount = await fakes.diagnostics.modelLoadCount()

        XCTAssertEqual(prepareCount, 0)
        XCTAssertEqual(modelLoadCount, 0)
        XCTAssertEqual(snapshot.model, .missing(modelID: RuntimeActiveModel.fixture.id))
    }

    func testBeginRecordingRefreshesReadinessBeforeStartingAudio() async {
        let fakes = RuntimeFakes.ready()
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)

        let snapshotCount = await fakes.permissions.snapshotCount()
        let startCount = await fakes.audio.startCount()
        XCTAssertEqual(snapshotCount, 1)
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(service.status, .recording(speechDetected: false))
    }

    func testBeginRecordingUsesActiveModelMaximumDuration() async {
        let fakes = RuntimeFakes.ready()
        await fakes.models.setActiveModel(.fixtureWithMaximumAudioSeconds(18))
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)

        let maximumDuration = await fakes.audio.lastMaximumDurationSeconds()
        XCTAssertEqual(maximumDuration, 18)
    }

    func testExcludedAppAtKeyDownDoesNotStartActivationOrAudioAndHidesOnRelease() async {
        let target = InsertionTargetIdentity.fixture
        var preferences = AppPreferences.defaults
        preferences.excludedApps = [
            ExcludedApp(
                bundleIdentifier: target.bundleIdentifier!,
                displayName: "Fixture"
            )
        ]
        let fakes = RuntimeFakes.ready(preferences: preferences, target: target)
        let service = AppDictationService(dependencies: fakes.dependencies)

        let downAction = await service.handleTriggerEvent(.triggerDown(timestampMs: 0))
        let startCount = await fakes.audio.startCount()

        XCTAssertEqual(downAction, .none)
        XCTAssertEqual(service.status, .blocked(.excludedApp))
        XCTAssertEqual(fakes.clock.sleepCount(), 0)
        XCTAssertEqual(startCount, 0)
        await waitUntil { await fakes.diagnostics.excludedAppBlockCount() == 1 }

        let upAction = await service.handleTriggerEvent(.triggerUp(timestampMs: 50))

        XCTAssertEqual(upAction, .none)
        XCTAssertEqual(service.status, .idle)
    }

    func testMissingFrontmostTargetSilentlySkipsRecording() async {
        let fakes = RuntimeFakes.ready(target: nil)
        let service = AppDictationService(dependencies: fakes.dependencies)

        let action = await service.handleTriggerEvent(.triggerDown(timestampMs: 0))
        let startCount = await fakes.audio.startCount()

        XCTAssertEqual(action, .none)
        XCTAssertEqual(service.status, .idle)
        XCTAssertEqual(fakes.clock.sleepCount(), 0)
        XCTAssertEqual(startCount, 0)
    }

    func testDismissTerminalStatusReturnsFailureToIdle() async {
        let fakes = RuntimeFakes.blocked(blocker: .microphonePermissionDenied)
        let service = AppDictationService(dependencies: fakes.dependencies)
        await service.handleTriggerAction(.beginRecording)
        XCTAssertEqual(service.status, .blocked(.readinessBlocked(.microphonePermissionDenied)))

        service.dismissTerminalStatus()

        XCTAssertEqual(service.status, .idle)
    }

    func testDismissTerminalStatusKeepsExcludedAppBlockedUntilRelease() async {
        let target = InsertionTargetIdentity.fixture
        var preferences = AppPreferences.defaults
        preferences.excludedApps = [
            ExcludedApp(bundleIdentifier: target.bundleIdentifier!, displayName: "Fixture")
        ]
        let fakes = RuntimeFakes.ready(preferences: preferences, target: target)
        let service = AppDictationService(dependencies: fakes.dependencies)
        _ = await service.handleTriggerEvent(.triggerDown(timestampMs: 0))

        service.dismissTerminalStatus()

        XCTAssertEqual(service.status, .blocked(.excludedApp))
    }

    func testReleaseWhileTargetCaptureIsSuspendedDoesNotArmActivation() async {
        let fakes = RuntimeFakes.ready()
        await fakes.targetCapturer.setSuspendUntilReleased(true)
        let service = AppDictationService(dependencies: fakes.dependencies)

        let downTask = Task {
            await service.handleTriggerEvent(.triggerDown(timestampMs: 0))
        }
        await waitUntil { await fakes.targetCapturer.isSuspended() }

        let upAction = await service.handleTriggerEvent(.triggerUp(timestampMs: 10))
        await fakes.targetCapturer.release()
        let downAction = await downTask.value
        let startCount = await fakes.audio.startCount()

        XCTAssertEqual(upAction, .none)
        XCTAssertEqual(downAction, .none)
        XCTAssertEqual(fakes.clock.sleepCount(), 0)
        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(service.status, .idle)
    }

    func testShortcutWhileTargetCaptureIsSuspendedDoesNotArmActivation() async {
        let fakes = RuntimeFakes.ready()
        await fakes.targetCapturer.setSuspendUntilReleased(true)
        let service = AppDictationService(dependencies: fakes.dependencies)

        let downTask = Task {
            await service.handleTriggerEvent(.triggerDown(timestampMs: 0))
        }
        await waitUntil { await fakes.targetCapturer.isSuspended() }

        let shortcutAction = await service.handleTriggerEvent(
            .nonTriggerKeyDown(timestampMs: 10, isModifierOnly: false)
        )
        await fakes.targetCapturer.release()
        let downAction = await downTask.value
        let startCount = await fakes.audio.startCount()

        XCTAssertEqual(shortcutAction, .none)
        XCTAssertEqual(downAction, .none)
        XCTAssertEqual(fakes.clock.sleepCount(), 0)
        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(service.status, .idle)
    }

    func testReadinessBlockerPreventsAudioStart() async {
        let fakes = RuntimeFakes.blocked(blocker: .microphonePermissionDenied)
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)

        let startCount = await fakes.audio.startCount()
        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(service.status, .blocked(.readinessBlocked(.microphonePermissionDenied)))
    }

    func testCancellationDuringTranscriptionPreventsLateInsertion() async {
        let fakes = RuntimeFakes.ready(transcript: "late text")
        await fakes.transcriber.setSuspendUntilReleased(true)
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        let task = Task { await service.handleTriggerAction(.finishRecording) }
        await waitUntil { await fakes.transcriber.isSuspended() }

        await service.cancelActiveSession(reason: .escapeKey)
        await fakes.transcriber.release()
        await task.value

        let insertedTexts = await fakes.inserter.insertedTexts()
        XCTAssertEqual(insertedTexts, [])
        XCTAssertEqual(service.status, .cancelled(.escapeKey))
    }

    func testLateSpeechCallbackDuringProcessingDoesNotReturnToRecording() async {
        let fakes = RuntimeFakes.ready()
        await fakes.transcriber.setSuspendUntilReleased(true)
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        let task = Task { await service.handleTriggerAction(.finishRecording) }
        await waitUntil { await fakes.transcriber.isSuspended() }

        await fakes.audio.emitSpeech(callbackIndex: 0)
        await settle()

        XCTAssertEqual(service.status, .processing)
        await fakes.transcriber.release()
        await task.value
    }

    func testStartRecordingErrorAfterCancellationKeepsCancellationStatus() async {
        let fakes = RuntimeFakes.ready()
        await fakes.audio.setSuspendStartUntilReleased(true)
        await fakes.audio.setStartError(LiveAudioRecorderError.engineStartFailed)
        let service = AppDictationService(dependencies: fakes.dependencies)

        let task = Task { await service.handleTriggerAction(.beginRecording) }
        await waitUntil { await fakes.audio.isStartSuspended() }
        await service.cancelActiveSession(reason: .escapeKey)
        await fakes.audio.releaseStart()
        await task.value

        XCTAssertEqual(service.status, .cancelled(.escapeKey))
    }

    func testFinishRecordingErrorAfterCancellationKeepsCancellationStatus() async {
        let fakes = RuntimeFakes.ready()
        await fakes.audio.suspendFinish(callNumber: 1)
        await fakes.audio.setFinishError(LiveAudioRecorderError.engineStartFailed)
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        let task = Task { await service.handleTriggerAction(.finishRecording) }
        await waitUntil { await fakes.audio.suspendedFinishCall() == 1 }

        await service.cancelActiveSession(reason: .escapeKey)
        await fakes.audio.releaseFinish()
        await task.value

        XCTAssertEqual(service.status, .cancelled(.escapeKey))
    }

    func testPrepareErrorAfterCancellationKeepsCancellationStatus() async {
        let fakes = RuntimeFakes.ready()
        await fakes.transcriber.setSuspendPrepareUntilReleased(true)
        await fakes.transcriber.setPrepareError(WhisperRuntimeError.loadFailed("fixture"))
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        let task = Task { await service.handleTriggerAction(.finishRecording) }
        await waitUntil { await fakes.transcriber.isPrepareSuspended() }

        await service.cancelActiveSession(reason: .escapeKey)
        await fakes.transcriber.releasePrepare()
        await task.value

        XCTAssertEqual(service.status, .cancelled(.escapeKey))
    }

    func testTranscriptionErrorAfterCancellationKeepsCancellationStatus() async {
        let fakes = RuntimeFakes.ready()
        await fakes.transcriber.setSuspendUntilReleased(true)
        await fakes.transcriber.setTranscribeError(WhisperRuntimeError.transcriptionFailed("fixture"))
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        let task = Task { await service.handleTriggerAction(.finishRecording) }
        await waitUntil { await fakes.transcriber.isSuspended() }

        await service.cancelActiveSession(reason: .escapeKey)
        await fakes.transcriber.release()
        await task.value

        XCTAssertEqual(service.status, .cancelled(.escapeKey))
    }

    func testDuplicateFinishWhileFirstFinishIsSuspendedDoesNotProcessTwice() async {
        let fakes = RuntimeFakes.ready(processedText: "insert once")
        await fakes.audio.suspendFinish(callNumber: 1)
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        let firstFinish = Task { await service.handleTriggerAction(.finishRecording) }
        await waitUntil { await fakes.audio.suspendedFinishCall() == 1 }

        await service.handleTriggerAction(.finishRecording)
        await fakes.audio.releaseFinish()
        await firstFinish.value

        let finishCount = await fakes.audio.finishCount()
        let transcribeCount = await fakes.transcriber.transcribeCount()
        let insertedTexts = await fakes.inserter.insertedTexts()
        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(transcribeCount, 1)
        XCTAssertEqual(insertedTexts, ["insert once"])
    }

    func testActivationTimerTokenIgnoresStaleTimerAfterCancellationAndRestart() async {
        let fakes = RuntimeFakes.ready()
        let service = AppDictationService(dependencies: fakes.dependencies)

        _ = await service.handleTriggerEvent(.triggerDown(timestampMs: 0))
        await waitUntil { fakes.clock.sleepCount() == 1 }
        await service.cancelActiveSession(reason: .escapeKey)
        _ = await service.handleTriggerEvent(.triggerUp(timestampMs: 10))

        _ = await service.handleTriggerEvent(.triggerDown(timestampMs: 20))
        await waitUntil { fakes.clock.sleepCount() == 2 }

        if fakes.clock.sleepCount() > 0 {
            fakes.clock.fireOldestSleep(nowMilliseconds: 250)
        }
        await settle()
        let startCountAfterStaleTimer = await fakes.audio.startCount()
        XCTAssertEqual(startCountAfterStaleTimer, 0)

        if fakes.clock.sleepCount() > 0 {
            fakes.clock.fireOldestSleep(nowMilliseconds: 270)
        }
        await waitUntil { await fakes.audio.startCount() == 1 }
        XCTAssertEqual(service.status, .recording(speechDetected: false))
    }

    func testReleaseBeforeActivationReturnsIdleAndStaleTimerDoesNotStartAudio() async {
        let fakes = RuntimeFakes.ready()
        let service = AppDictationService(dependencies: fakes.dependencies)

        _ = await service.handleTriggerEvent(.triggerDown(timestampMs: 0))
        await waitUntil { fakes.clock.sleepCount() == 1 }
        _ = await service.handleTriggerEvent(.triggerUp(timestampMs: 120))

        fakes.clock.fireOldestSleep(nowMilliseconds: 250)
        await settle()

        let startCount = await fakes.audio.startCount()
        XCTAssertEqual(service.status, .idle)
        XCTAssertEqual(startCount, 0)
    }

    func testCancellationWhileReadinessLoadIsSuspendedPreventsAudioStart() async {
        let fakes = RuntimeFakes.ready()
        await fakes.settings.suspendLoad(callNumber: 1)
        let service = AppDictationService(dependencies: fakes.dependencies)

        let task = Task { await service.handleTriggerAction(.beginRecording) }
        await waitUntil { await fakes.settings.suspendedLoadCall() == 1 }
        await service.cancelActiveSession(reason: .escapeKey)
        await fakes.settings.releaseLoad()
        await task.value

        let startCount = await fakes.audio.startCount()
        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(service.status, .cancelled(.escapeKey))
    }

    func testReleaseWhileSettingsLoadIsSuspendedPreventsAudioStart() async {
        let fakes = RuntimeFakes.ready()
        await fakes.settings.suspendLoad(callNumber: 2)
        let service = AppDictationService(dependencies: fakes.dependencies)

        let task = Task { await service.handleTriggerAction(.beginRecording) }
        await waitUntil { await fakes.settings.suspendedLoadCall() == 2 }
        await service.handleTriggerAction(.discardRecording)
        await fakes.settings.releaseLoad()
        await task.value

        let startCount = await fakes.audio.startCount()
        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(service.status, .cancelled(.noSpeechDetected))
    }

    func testSecondTriggerDuringTranscriptionCannotStealActiveSession() async {
        let fakes = RuntimeFakes.ready(transcript: "first result", processedText: "first result")
        await fakes.transcriber.setSuspendUntilReleased(true)
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        let task = Task { await service.handleTriggerAction(.finishRecording) }
        await waitUntil { await fakes.transcriber.isSuspended() }

        _ = await service.handleTriggerEvent(.triggerDown(timestampMs: 1_000))
        await settle()
        if fakes.clock.sleepCount() > 0 {
            fakes.clock.fireOldestSleep(nowMilliseconds: 1_250)
        }
        await settle()
        await fakes.transcriber.release()
        await task.value

        let startCount = await fakes.audio.startCount()
        let insertedTexts = await fakes.inserter.insertedTexts()
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(insertedTexts, ["first result"])
        XCTAssertEqual(service.status, .completed(textLengthBucket: "1-50"))
    }

    func testSpeechDetectedCallbackUpdatesStatusOnlyForActiveSession() async {
        let fakes = RuntimeFakes.ready()
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await service.cancelActiveSession(reason: .escapeKey)
        await service.handleTriggerAction(.beginRecording)

        await fakes.audio.emitSpeech(callbackIndex: 0)
        await settle()
        XCTAssertEqual(service.status, .recording(speechDetected: false))

        await fakes.audio.emitSpeech(callbackIndex: 1)
        await settle()
        XCTAssertEqual(service.status, .recording(speechDetected: true))
    }

    func testFinishWithEmptyAudioCancelsNoSpeechDetected() async {
        let fakes = RuntimeFakes.ready(audio: CanonicalAudioBuffer(samples: []))
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await service.handleTriggerAction(.finishRecording)

        XCTAssertEqual(service.status, .cancelled(.noSpeechDetected))
        let insertedTexts = await fakes.inserter.insertedTexts()
        let transcribeCount = await fakes.transcriber.transcribeCount()
        XCTAssertEqual(insertedTexts, [])
        XCTAssertEqual(transcribeCount, 0)
    }

    func testMaximumDurationAutomaticallyFinishesActiveRecording() async {
        let fakes = RuntimeFakes.ready(processedText: "duration capped")
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await fakes.audio.emitMaximumDuration(callbackIndex: 0)
        await waitUntil { service.status == .completed(textLengthBucket: "1-50") }
        let finishCount = await fakes.audio.finishCount()
        let insertedTexts = await fakes.inserter.insertedTexts()

        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(insertedTexts, ["duration capped"])
    }

    func testCurrentSegmentFinishesWhenActiveSelectionDisappears() async {
        let fakes = RuntimeFakes.ready()
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await fakes.models.setActiveModel(nil)
        await service.handleTriggerAction(.finishRecording)

        XCTAssertEqual(service.status, .completed(textLengthBucket: "1-50"))
        let insertedTexts = await fakes.inserter.insertedTexts()
        let transcribeCount = await fakes.transcriber.transcribeCount()
        XCTAssertEqual(insertedTexts, ["hello period"])
        XCTAssertEqual(transcribeCount, 1)
    }

    func testTranscriberLoadingReadinessBlocksRefreshAndRecordingStart() async {
        await assertTranscriberReadinessBlocks(
            .loading(modelID: RuntimeActiveModel.fixture.id),
            expectedBlocker: .activeModelNotReady(modelID: RuntimeActiveModel.fixture.id)
        )
    }

    func testTranscriberWarmingReadinessBlocksRefreshAndRecordingStart() async {
        await assertTranscriberReadinessBlocks(
            .warming(modelID: RuntimeActiveModel.fixture.id),
            expectedBlocker: .activeModelNotReady(modelID: RuntimeActiveModel.fixture.id)
        )
    }

    func testTranscriberFailedReadinessBlocksRefreshAndRecordingStart() async {
        await assertTranscriberReadinessBlocks(
            .failed(modelID: RuntimeActiveModel.fixture.id, reason: .warmupFailed),
            expectedBlocker: .transcriptionRuntimeFailed(modelID: RuntimeActiveModel.fixture.id)
        )
    }

    func testSuccessfulFinishPreparesTranscribesPostProcessesInsertsAndCompletesWithLengthBucket() async {
        let processed = String(repeating: "a", count: 51)
        let fakes = RuntimeFakes.ready(transcript: "raw transcript", processedText: processed)
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await service.handleTriggerAction(.finishRecording)

        let prepareCount = await fakes.transcriber.prepareCount()
        let transcribeCount = await fakes.transcriber.transcribeCount()
        let processedRawTexts = await fakes.postProcessor.processedRawTexts()
        let insertedTexts = await fakes.inserter.insertedTexts()
        let diagnosticCount = await fakes.diagnostics.transcriptionCompletionCount()
        let insertionDiagnosticCount = await fakes.diagnostics.insertionAttemptCount()
        XCTAssertEqual(prepareCount, 1)
        XCTAssertEqual(transcribeCount, 1)
        XCTAssertEqual(processedRawTexts, ["raw transcript"])
        XCTAssertEqual(insertedTexts, [processed])
        XCTAssertEqual(service.status, .completed(textLengthBucket: "51-200"))
        XCTAssertEqual(diagnosticCount, 1)
        XCTAssertEqual(insertionDiagnosticCount, 1)
    }

    func testVoiceCleaningRunsBeforeASRWhenSelected() async {
        var preferences = AppPreferences.defaults
        preferences.activeVoiceCleaningModelID = RuntimeActiveModel.voiceCleanerFixture.id
        let original = CanonicalAudioBuffer(samples: [0.1, 0.2, 0.3])
        let cleaned = TranscriptionAudioBuffer(samples: [0.7, 0.8, 0.9])
        let fakes = RuntimeFakes.ready(audio: original, preferences: preferences)
        await fakes.models.setVoiceCleaningModel(.voiceCleanerFixture)
        await fakes.voiceCleaner.setOutput(cleaned)
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await service.handleTriggerAction(.finishRecording)

        let transcribedAudio = await fakes.transcriber.lastAudio()
        let cleaningCallCount = await fakes.voiceCleaner.cleanCallCount()
        let diagnosticCount = await fakes.diagnostics.voiceCleaningCount()
        XCTAssertEqual(transcribedAudio, cleaned)
        XCTAssertEqual(cleaningCallCount, 1)
        XCTAssertEqual(diagnosticCount, 1)
        XCTAssertEqual(
            service.voiceCleaningStatus,
            .ready(modelID: RuntimeActiveModel.voiceCleanerFixture.id)
        )
    }

    func testVoiceCleaningFailureFallsBackToOriginalAudioAndWarns() async {
        var preferences = AppPreferences.defaults
        preferences.activeVoiceCleaningModelID = RuntimeActiveModel.voiceCleanerFixture.id
        let original = CanonicalAudioBuffer(samples: [0.1, 0.2, 0.3])
        let fakes = RuntimeFakes.ready(audio: original, preferences: preferences)
        await fakes.models.setVoiceCleaningModel(.voiceCleanerFixture)
        await fakes.voiceCleaner.setCleanError(FakeVoiceCleaningError.failed)
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await service.handleTriggerAction(.finishRecording)

        let transcribedAudio = await fakes.transcriber.lastAudio()
        XCTAssertEqual(
            transcribedAudio,
            TranscriptionAudioBuffer(samples: original.samples)
        )
        XCTAssertEqual(
            service.voiceCleaningStatus,
            .warning(
                modelID: RuntimeActiveModel.voiceCleanerFixture.id,
                reason: .processingFailed
            )
        )
        let diagnosticCount = await fakes.diagnostics.voiceCleaningCount()
        XCTAssertEqual(diagnosticCount, 1)
        XCTAssertEqual(service.status, .completed(textLengthBucket: "1-50"))
    }

    func testHallucinationSignalsSilentlyDiscardBeforePostProcessingAndInsertion() async {
        let suspiciousResults = [
            TranscriptionResult(
                text: "plausible words",
                noSpeechProbability: 0.61,
                averageLogProbability: -0.1,
                compressionRatio: 1.0
            ),
            TranscriptionResult(
                text: "plausible words",
                noSpeechProbability: 0.1,
                averageLogProbability: -1.01,
                compressionRatio: 1.0
            ),
            TranscriptionResult(
                text: "plausible words",
                noSpeechProbability: 0.1,
                averageLogProbability: -0.1,
                compressionRatio: 2.41
            ),
            TranscriptionResult(
                text: "Thanks for watching!",
                noSpeechProbability: 0.1,
                averageLogProbability: -0.1,
                compressionRatio: 1.0
            )
        ]

        for result in suspiciousResults {
            let fakes = RuntimeFakes.ready(transcriptionResult: result)
            let service = AppDictationService(dependencies: fakes.dependencies)

            await service.handleTriggerAction(.beginRecording)
            await service.handleTriggerAction(.finishRecording)

            let insertedTexts = await fakes.inserter.insertedTexts()
            let processedRawTexts = await fakes.postProcessor.processedRawTexts()
            let diagnosticCount = await fakes.diagnostics.transcriptionDiscardCount()
            XCTAssertEqual(insertedTexts, [])
            XCTAssertEqual(processedRawTexts, [])
            XCTAssertEqual(service.status, .idle)
            XCTAssertEqual(diagnosticCount, 1)
        }
    }

    func testEmptyProcessedTextDoesNotInsertAndReturnsIdle() async {
        let fakes = RuntimeFakes.ready(transcript: "raw transcript", processedText: " \n ")
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await service.handleTriggerAction(.finishRecording)

        let insertedTexts = await fakes.inserter.insertedTexts()
        XCTAssertEqual(insertedTexts, [])
        XCTAssertEqual(service.status, .idle)
    }

    func testInsertionFailureMapsToFailedInsertionFailed() async {
        let fakes = RuntimeFakes.ready(processedText: "insert me")
        await fakes.inserter.setOutcome(.notInserted(.pasteEventFailed))
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await service.handleTriggerAction(.finishRecording)

        XCTAssertEqual(service.status, .failed(.insertionFailed))
    }

    func testTargetChangeDuringInsertionSilentlyReturnsIdle() async {
        let fakes = RuntimeFakes.ready(processedText: "insert me")
        await fakes.inserter.setOutcome(.notInserted(.targetChanged))
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await service.handleTriggerAction(.finishRecording)

        XCTAssertEqual(service.status, .idle)
    }

    func testSecureInsertionTargetSilentlyReturnsIdle() async {
        let fakes = RuntimeFakes.ready(processedText: "insert me")
        await fakes.inserter.setOutcome(.notInserted(.blockedTarget(.secureFieldFocused)))
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await service.handleTriggerAction(.finishRecording)

        XCTAssertEqual(service.status, .idle)
    }

    func testCancellationDuringInsertionKeepsInsertionOutcome() async {
        let fakes = RuntimeFakes.ready(processedText: "insert me")
        await fakes.inserter.setSuspendUntilReleased(true)
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        let task = Task { await service.handleTriggerAction(.finishRecording) }
        await waitUntil { await fakes.inserter.isSuspended() }

        await service.cancelActiveSession(reason: .escapeKey)
        await fakes.inserter.release()
        await task.value

        let insertedTexts = await fakes.inserter.insertedTexts()
        XCTAssertEqual(insertedTexts, ["insert me"])
        XCTAssertEqual(service.status, .completed(textLengthBucket: "1-50"))
    }

    func testAudioFinishFailureMapsToFailedAudioFinishFailed() async {
        let fakes = RuntimeFakes.ready()
        await fakes.audio.setFinishError(LiveAudioRecorderError.engineStartFailed)
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await service.handleTriggerAction(.finishRecording)

        XCTAssertEqual(service.status, .failed(.audioFinishFailed))
        let insertedTexts = await fakes.inserter.insertedTexts()
        XCTAssertEqual(insertedTexts, [])
    }

    func testAudioEmptyRecordingErrorMapsToCancelledNoSpeechDetected() async {
        let fakes = RuntimeFakes.ready()
        await fakes.audio.setFinishError(LiveAudioRecorderError.emptyRecording)
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await service.handleTriggerAction(.finishRecording)

        XCTAssertEqual(service.status, .cancelled(.noSpeechDetected))
        let insertedTexts = await fakes.inserter.insertedTexts()
        XCTAssertEqual(insertedTexts, [])
    }

    func testAudioConversionFinishErrorsMapToAudioConversionFailed() async {
        await assertAudioFinishError(
            LiveAudioRecorderError.conversionFailed,
            mapsTo: .failed(.audioConversionFailed)
        )
        await assertAudioFinishError(
            LiveAudioRecorderError.unsupportedInputFormat,
            mapsTo: .failed(.audioConversionFailed)
        )
    }

    func testAudioDeviceChangeDuringRecordingMapsToMicrophoneChanged() async {
        await assertAudioFinishError(
            LiveAudioRecorderError.deviceChangedDuringRecording,
            mapsTo: .failed(.microphoneChanged)
        )
    }

    func testTranscriptionFailureMapsToFailedTranscriptionFailed() async {
        let fakes = RuntimeFakes.ready()
        await fakes.transcriber.setTranscribeError(WhisperRuntimeError.transcriptionFailed("fixture"))
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await service.handleTriggerAction(.finishRecording)

        XCTAssertEqual(service.status, .failed(.transcriptionFailed))
        let insertedTexts = await fakes.inserter.insertedTexts()
        XCTAssertEqual(insertedTexts, [])
        let failures = await fakes.diagnostics.runtimeFailures()
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.stage, "inference")
        XCTAssertEqual(failures.first?.reasonCode, "inference_failed")
    }

    private func assertTranscriberReadinessBlocks(
        _ transcriberReadiness: RuntimeModelReadiness,
        expectedBlocker: ReadinessBlocker,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let fakes = RuntimeFakes.ready()
        await fakes.transcriber.setReadiness(transcriberReadiness)
        let service = AppDictationService(dependencies: fakes.dependencies)

        let snapshot = await service.refreshReadiness()
        XCTAssertEqual(snapshot.model, transcriberReadiness, file: file, line: line)
        XCTAssertEqual(snapshot.blockers, [expectedBlocker], file: file, line: line)

        await service.handleTriggerAction(.beginRecording)

        let startCount = await fakes.audio.startCount()
        XCTAssertEqual(startCount, 0, file: file, line: line)
        XCTAssertEqual(service.status, .blocked(.readinessBlocked(expectedBlocker)), file: file, line: line)
    }

    private func assertAudioFinishError(
        _ error: LiveAudioRecorderError,
        mapsTo expectedStatus: DictationRuntimeStatus,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let fakes = RuntimeFakes.ready()
        await fakes.audio.setFinishError(error)
        let service = AppDictationService(dependencies: fakes.dependencies)

        await service.handleTriggerAction(.beginRecording)
        await service.handleTriggerAction(.finishRecording)

        XCTAssertEqual(service.status, expectedStatus, file: file, line: line)
    }

    private func settle() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }

    private func waitUntil(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () async -> Bool
    ) async {
        for _ in 0..<1_000 {
            if await condition() {
                return
            }
            await Task.yield()
        }

        XCTFail("Timed out waiting for condition", file: file, line: line)
    }
}

private actor PurposeRuntimeBoundaryGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func isWaiting() -> Bool {
        continuation != nil
    }

    func release() {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}

private struct RuntimeFakes {
    let settings: FakeRuntimeSettings
    let permissions: FakeRuntimePermissions
    let models: FakeRuntimeModels
    let audio: FakeRuntimeAudio
    let transcriber: FakeRuntimeTranscriber
    let voiceCleaner: FakeRuntimeVoiceCleaner
    let targetCapturer: FakeRuntimeTargetCapturer
    let inserter: FakeInsertionService
    let diagnostics: FakeRuntimeDiagnostics
    let postProcessor: FakeRuntimePostProcessor
    let clock: FakeRuntimeClock

    var dependencies: RuntimeDependencies {
        RuntimeDependencies(
            settings: settings,
            permissions: permissions,
            models: models,
            audio: audio,
            transcriber: transcriber,
            voiceCleaner: voiceCleaner,
            targetCapturer: targetCapturer,
            inserter: inserter,
            diagnostics: diagnostics,
            postProcessor: postProcessor,
            clock: clock
        )
    }

    static func ready(
        audio: CanonicalAudioBuffer = CanonicalAudioBuffer(samples: [0.1, 0.2, 0.3]),
        transcript: String = "hello period",
        processedText: String? = nil,
        transcriptionResult: TranscriptionResult? = nil,
        preferences: AppPreferences = .defaults,
        target: InsertionTargetIdentity? = .fixture
    ) -> RuntimeFakes {
        RuntimeFakes(
            settings: FakeRuntimeSettings(preferences: preferences),
            permissions: FakeRuntimePermissions(
                snapshot: RuntimePermissionSnapshot(
                    microphone: .granted,
                    accessibility: .granted,
                    inputMonitoring: .granted
                )
            ),
            models: FakeRuntimeModels(activeModel: .fixture),
            audio: FakeRuntimeAudio(audio: audio),
            transcriber: transcriptionResult.map(FakeRuntimeTranscriber.init(result:))
                ?? FakeRuntimeTranscriber(transcript: transcript),
            voiceCleaner: FakeRuntimeVoiceCleaner(),
            targetCapturer: FakeRuntimeTargetCapturer(target: target),
            inserter: FakeInsertionService(),
            diagnostics: FakeRuntimeDiagnostics(),
            postProcessor: FakeRuntimePostProcessor(processedText: processedText),
            clock: FakeRuntimeClock()
        )
    }

    static func blocked(blocker: ReadinessBlocker) -> RuntimeFakes {
        switch blocker {
        case .microphonePermissionDenied:
            return fixture(
                snapshot: RuntimePermissionSnapshot(
                    microphone: .denied,
                    accessibility: .granted,
                    inputMonitoring: .granted
                )
            )
        case .accessibilityPermissionDenied:
            return fixture(
                snapshot: RuntimePermissionSnapshot(
                    microphone: .granted,
                    accessibility: .denied,
                    inputMonitoring: .granted
                )
            )
        case .noActiveModel:
            return fixture(activeModel: nil, readiness: .noActiveModel)
        case let .activeModelMissing(modelID):
            return fixture(activeModel: .fixture, readiness: .missing(modelID: modelID))
        case let .activeModelNotReady(modelID):
            return fixture(activeModel: .fixture, readiness: .loading(modelID: modelID))
        case let .transcriptionRuntimeFailed(modelID):
            return fixture(activeModel: .fixture, readiness: .failed(modelID: modelID, reason: .loadFailed))
        case let .activeModelRevoked(modelID):
            return fixture(
                activeModel: .fixture,
                readiness: .revoked(modelID: modelID)
            )
        }
    }

    private static func fixture(
        snapshot: RuntimePermissionSnapshot = RuntimePermissionSnapshot(
            microphone: .granted,
            accessibility: .granted,
            inputMonitoring: .granted
        ),
        activeModel: RuntimeActiveModel? = .fixture,
        readiness: RuntimeModelReadiness? = nil
    ) -> RuntimeFakes {
        RuntimeFakes(
            settings: FakeRuntimeSettings(preferences: .defaults),
            permissions: FakeRuntimePermissions(snapshot: snapshot),
            models: FakeRuntimeModels(activeModel: activeModel, readiness: readiness),
            audio: FakeRuntimeAudio(audio: CanonicalAudioBuffer(samples: [0.1, 0.2, 0.3])),
            transcriber: FakeRuntimeTranscriber(transcript: "hello period"),
            voiceCleaner: FakeRuntimeVoiceCleaner(),
            targetCapturer: FakeRuntimeTargetCapturer(target: .fixture),
            inserter: FakeInsertionService(),
            diagnostics: FakeRuntimeDiagnostics(),
            postProcessor: FakeRuntimePostProcessor(processedText: nil),
            clock: FakeRuntimeClock()
        )
    }
}

private actor FakeRuntimeTargetCapturer: InsertionTargetCapturing {
    private var target: InsertionTargetIdentity?
    private var suspendUntilReleased = false
    private var suspensionContinuation: CheckedContinuation<Void, Never>?

    init(target: InsertionTargetIdentity?) {
        self.target = target
    }

    func currentTargetIdentity() async -> InsertionTargetIdentity? {
        if suspendUntilReleased {
            await withCheckedContinuation { continuation in
                suspensionContinuation = continuation
            }
        }
        return target
    }

    func setTarget(_ target: InsertionTargetIdentity?) {
        self.target = target
    }

    func setSuspendUntilReleased(_ suspendUntilReleased: Bool) {
        self.suspendUntilReleased = suspendUntilReleased
    }

    func isSuspended() -> Bool {
        suspensionContinuation != nil
    }

    func release() {
        suspendUntilReleased = false
        let continuation = suspensionContinuation
        suspensionContinuation = nil
        continuation?.resume()
    }
}

private actor FakeRuntimeSettings: RuntimeSettingsProviding {
    private var preferences: AppPreferences
    private var loadCallCount = 0
    private var suspendedLoadCallValue: Int?
    private var suspendedCallNumbers: Set<Int> = []
    private var suspensionContinuation: CheckedContinuation<Void, Never>?

    init(preferences: AppPreferences) {
        self.preferences = preferences
    }

    func loadPreferences() async -> AppPreferences {
        loadCallCount += 1
        let callNumber = loadCallCount
        if suspendedCallNumbers.contains(callNumber) {
            suspendedLoadCallValue = callNumber
            await withCheckedContinuation { continuation in
                suspensionContinuation = continuation
            }
        }
        return preferences
    }

    func savePreferences(_ preferences: AppPreferences) async {
        self.preferences = preferences
    }

    func suspendLoad(callNumber: Int) {
        suspendedCallNumbers.insert(callNumber)
    }

    func suspendedLoadCall() -> Int? {
        suspendedLoadCallValue
    }

    func releaseLoad() {
        let continuation = suspensionContinuation
        suspensionContinuation = nil
        suspendedLoadCallValue = nil
        continuation?.resume()
    }
}

private actor FakeRuntimePermissions: RuntimePermissionChecking {
    private var snapshot: RuntimePermissionSnapshot
    private var snapshotCountValue = 0

    func snapshotCount() -> Int {
        snapshotCountValue
    }

    init(snapshot: RuntimePermissionSnapshot) {
        self.snapshot = snapshot
    }

    func permissionSnapshot() async -> RuntimePermissionSnapshot {
        snapshotCountValue += 1
        return snapshot
    }

}

private actor FakeRuntimeModels: RuntimeModelResolving {
    private var activeModel: RuntimeActiveModel?
    private var voiceCleaningModel: RuntimeActiveModel?
    private var selectableModelsByID: [String: RuntimeActiveModel] = [:]
    private var selectableVoiceCleaningModelsByID:
        [String: RuntimeActiveModel] = [:]
    private var readinessOverride: RuntimeModelReadiness?
    private var suspendVoiceCleaningResolution = false
    private var voiceCleaningResolutionContinuation:
        CheckedContinuation<Void, Never>?

    init(activeModel: RuntimeActiveModel?, readiness: RuntimeModelReadiness? = nil) {
        self.activeModel = activeModel
        self.readinessOverride = readiness
    }

    func resolveActiveModel(preferences: AppPreferences) async -> RuntimeActiveModel? {
        if let modelID = preferences.activeModelID,
           let selectableModel = selectableModelsByID[modelID] {
            return selectableModel
        }
        return activeModel
    }

    func readiness(for model: RuntimeActiveModel?) async -> RuntimeModelReadiness {
        if let readinessOverride {
            return readinessOverride
        }
        guard let model else {
            return .noActiveModel
        }
        return .ready(modelID: model.id)
    }

    func resolveActiveVoiceCleaningModel(preferences: AppPreferences) async -> RuntimeActiveModel? {
        if suspendVoiceCleaningResolution {
            await withCheckedContinuation { continuation in
                voiceCleaningResolutionContinuation = continuation
            }
        }
        if let modelID = preferences.activeVoiceCleaningModelID,
           let selectableModel = selectableVoiceCleaningModelsByID[modelID] {
            return selectableModel
        }
        return voiceCleaningModel
    }

    func setActiveModel(_ activeModel: RuntimeActiveModel?) {
        self.activeModel = activeModel
        readinessOverride = nil
    }

    func setVoiceCleaningModel(_ model: RuntimeActiveModel?) {
        voiceCleaningModel = model
    }

    func setSelectableModels(_ models: [RuntimeActiveModel]) {
        selectableModelsByID = Dictionary(
            uniqueKeysWithValues: models.map { ($0.id, $0) }
        )
    }

    func setSelectableVoiceCleaningModels(_ models: [RuntimeActiveModel]) {
        selectableVoiceCleaningModelsByID = Dictionary(
            uniqueKeysWithValues: models.map { ($0.id, $0) }
        )
    }

    func setSuspendVoiceCleaningResolution(_ shouldSuspend: Bool) {
        suspendVoiceCleaningResolution = shouldSuspend
    }

    func isVoiceCleaningResolutionSuspended() -> Bool {
        voiceCleaningResolutionContinuation != nil
    }

    func releaseVoiceCleaningResolution() {
        suspendVoiceCleaningResolution = false
        let continuation = voiceCleaningResolutionContinuation
        voiceCleaningResolutionContinuation = nil
        continuation?.resume()
    }

}

private actor FakeRuntimeAudio: RuntimeAudioRecording {
    private var audio: CanonicalAudioBuffer
    private var startError: Error?
    private var finishError: Error?
    private var callbacks: [@Sendable () -> Void] = []
    private var maximumDurationCallbacks: [@Sendable () -> Void] = []
    private var startCountValue = 0
    private var finishCountValue = 0
    private var maximumDurationSecondsValues: [Double] = []
    private var suspendStartUntilReleased = false
    private var startSuspensionContinuation: CheckedContinuation<Void, Never>?
    private var suspendedFinishCallNumbers: Set<Int> = []
    private var suspendedFinishCallValue: Int?
    private var finishSuspensionContinuation: CheckedContinuation<Void, Never>?

    func startCount() -> Int {
        startCountValue
    }

    func finishCount() -> Int {
        finishCountValue
    }

    func lastMaximumDurationSeconds() -> Double? {
        maximumDurationSecondsValues.last
    }

    func isStartSuspended() -> Bool {
        startSuspensionContinuation != nil
    }

    func suspendedFinishCall() -> Int? {
        suspendedFinishCallValue
    }

    init(audio: CanonicalAudioBuffer) {
        self.audio = audio
    }

    func startRecording(
        microphone: MicrophoneSelection,
        maximumDurationSeconds: Double,
        onSpeechDetected: @escaping @Sendable () -> Void,
        onMaximumDurationReached: @escaping @Sendable () -> Void
    ) async throws {
        startCountValue += 1
        maximumDurationSecondsValues.append(maximumDurationSeconds)
        if suspendStartUntilReleased {
            await withCheckedContinuation { continuation in
                startSuspensionContinuation = continuation
            }
        }
        if let startError {
            throw startError
        }
        callbacks.append(onSpeechDetected)
        maximumDurationCallbacks.append(onMaximumDurationReached)
    }

    func finishRecording() async throws -> CanonicalAudioBuffer {
        finishCountValue += 1
        let callNumber = finishCountValue
        if suspendedFinishCallNumbers.contains(callNumber) {
            suspendedFinishCallValue = callNumber
            await withCheckedContinuation { continuation in
                finishSuspensionContinuation = continuation
            }
        }
        if let finishError {
            throw finishError
        }
        return audio
    }

    func discardRecording() async {
    }

    func setFinishError(_ error: Error?) {
        finishError = error
    }

    func setStartError(_ error: Error?) {
        startError = error
    }

    func setSuspendStartUntilReleased(_ suspendStartUntilReleased: Bool) {
        self.suspendStartUntilReleased = suspendStartUntilReleased
    }

    func suspendFinish(callNumber: Int) {
        suspendedFinishCallNumbers.insert(callNumber)
    }

    func releaseStart() {
        let continuation = startSuspensionContinuation
        startSuspensionContinuation = nil
        continuation?.resume()
    }

    func releaseFinish() {
        let continuation = finishSuspensionContinuation
        finishSuspensionContinuation = nil
        suspendedFinishCallValue = nil
        continuation?.resume()
    }

    func emitSpeech(callbackIndex: Int) {
        guard callbacks.indices.contains(callbackIndex) else {
            return
        }
        callbacks[callbackIndex]()
    }

    func emitMaximumDuration(callbackIndex: Int) {
        guard maximumDurationCallbacks.indices.contains(callbackIndex) else {
            return
        }
        maximumDurationCallbacks[callbackIndex]()
    }
}

private actor FakeRuntimeTranscriber: RuntimeTranscribing {
    private let result: TranscriptionResult
    private var readinessValue: RuntimeModelReadiness
    private var prepareCountValue = 0
    private var preparedModelIDValues: [String] = []
    private var transcribeCountValue = 0
    private var prepareError: Error?
    private var transcribeError: Error?
    private var suspendPrepareUntilReleased = false
    private var suspendUntilReleased = false
    private var prepareSuspensionContinuation: CheckedContinuation<Void, Never>?
    private var suspensionContinuation: CheckedContinuation<Void, Never>?
    private var lastAudioValue: TranscriptionAudioBuffer?

    var readiness: RuntimeModelReadiness {
        get async {
            readinessValue
        }
    }

    func prepareCount() -> Int {
        prepareCountValue
    }

    func preparedModelIDs() -> [String] {
        preparedModelIDValues
    }

    func transcribeCount() -> Int {
        transcribeCountValue
    }

    func isSuspended() -> Bool {
        suspensionContinuation != nil
    }

    func isPrepareSuspended() -> Bool {
        prepareSuspensionContinuation != nil
    }

    init(transcript: String) {
        self.result = TranscriptionResult(
            text: transcript,
            noSpeechProbability: 0.01,
            averageLogProbability: -0.1,
            compressionRatio: 1.0
        )
        self.readinessValue = .noActiveModel
    }

    init(result: TranscriptionResult) {
        self.result = result
        self.readinessValue = .noActiveModel
    }

    func prepare(model: RuntimeActiveModel) async throws {
        prepareCountValue += 1
        preparedModelIDValues.append(model.id)
        if suspendPrepareUntilReleased {
            await withCheckedContinuation { continuation in
                prepareSuspensionContinuation = continuation
            }
        }
        if let prepareError {
            throw prepareError
        }
        readinessValue = .ready(modelID: model.id)
    }

    func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult {
        transcribeCountValue += 1
        lastAudioValue = audio
        if suspendUntilReleased {
            await withCheckedContinuation { continuation in
                suspensionContinuation = continuation
            }
        }
        if let transcribeError {
            throw transcribeError
        }
        return result
    }

    func unload() async {
        readinessValue = .noActiveModel
    }

    func lastAudio() -> TranscriptionAudioBuffer? {
        lastAudioValue
    }

    func setSuspendUntilReleased(_ suspendUntilReleased: Bool) {
        self.suspendUntilReleased = suspendUntilReleased
    }

    func setSuspendPrepareUntilReleased(_ suspendPrepareUntilReleased: Bool) {
        self.suspendPrepareUntilReleased = suspendPrepareUntilReleased
    }

    func setPrepareError(_ error: Error?) {
        self.prepareError = error
    }

    func setTranscribeError(_ error: Error?) {
        self.transcribeError = error
    }

    func setReadiness(_ readiness: RuntimeModelReadiness) {
        self.readinessValue = readiness
    }

    func release() {
        let continuation = suspensionContinuation
        suspensionContinuation = nil
        continuation?.resume()
    }

    func releasePrepare() {
        let continuation = prepareSuspensionContinuation
        prepareSuspensionContinuation = nil
        continuation?.resume()
    }
}

private enum FakeVoiceCleaningError: Error {
    case failed
}

private actor FakeRuntimeVoiceCleaner: RuntimeVoiceCleaning {
    private var output: TranscriptionAudioBuffer?
    private var prepareError: Error?
    private var prepareCalls = 0
    private var preparedModelIDValues: [String] = []
    private var cleanError: Error?
    private var cleanCalls = 0

    func prepare(model: RuntimeActiveModel) async throws {
        prepareCalls += 1
        preparedModelIDValues.append(model.id)
        if let prepareError {
            throw prepareError
        }
    }

    func clean(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionAudioBuffer {
        cleanCalls += 1
        if let cleanError {
            throw cleanError
        }
        return output ?? audio
    }

    func unload() async {}

    func setOutput(_ output: TranscriptionAudioBuffer?) {
        self.output = output
    }

    func setPrepareError(_ error: Error?) {
        prepareError = error
    }

    func prepareCallCount() -> Int {
        prepareCalls
    }

    func preparedModelIDs() -> [String] {
        preparedModelIDValues
    }

    func setCleanError(_ error: Error?) {
        cleanError = error
    }

    func cleanCallCount() -> Int {
        cleanCalls
    }
}

private actor FakeInsertionService: InsertionService {
    private var outcome: InsertionOutcome = .pasted(
        PasteInsertionReport(pasteboardRestored: true, pasteboardRestoreFailed: false)
    )
    private var insertedTextsValue: [String] = []
    private var suspendUntilReleased = false
    private var suspensionContinuation: CheckedContinuation<Void, Never>?

    func insertedTexts() -> [String] {
        insertedTextsValue
    }

    func isSuspended() -> Bool {
        suspensionContinuation != nil
    }

    func insert(_ request: InsertionRequest) async -> InsertionOutcome {
        insertedTextsValue.append(request.text)
        if suspendUntilReleased {
            await withCheckedContinuation { continuation in
                suspensionContinuation = continuation
            }
        }
        return outcome
    }

    func setOutcome(_ outcome: InsertionOutcome) {
        self.outcome = outcome
    }

    func setSuspendUntilReleased(_ suspendUntilReleased: Bool) {
        self.suspendUntilReleased = suspendUntilReleased
    }

    func release() {
        let continuation = suspensionContinuation
        suspensionContinuation = nil
        continuation?.resume()
    }
}

private actor FakeRuntimeDiagnostics: RuntimeDiagnosticsLogging {
    private var transcriptionCompletionCountValue = 0
    private var transcriptionDiscardCountValue = 0
    private var excludedAppBlockCountValue = 0
    private var insertionAttemptCountValue = 0
    private var modelLoadCountValue = 0
    private var voiceCleaningCountValue = 0
    private var runtimeFailureValues: [(stage: String, reasonCode: String)] = []

    func log(_ event: DiagnosticEvent) async {
        switch event {
        case .transcriptionCompleted:
            transcriptionCompletionCountValue += 1
        case .transcriptionDiscarded:
            transcriptionDiscardCountValue += 1
        case .dictationBlockedExcludedApp:
            excludedAppBlockCountValue += 1
        case .insertionAttempt:
            insertionAttemptCountValue += 1
        case .modelLoad:
            modelLoadCountValue += 1
        case let .runtimeFailure(_, _, _, stage, reasonCode):
            runtimeFailureValues.append((stage, reasonCode))
        case .voiceCleaning:
            voiceCleaningCountValue += 1
        case .appStarted, .catalogUpdateRejected, .launchAtLoginChange:
            break
        }
    }

    func transcriptionCompletionCount() -> Int {
        transcriptionCompletionCountValue
    }

    func transcriptionDiscardCount() -> Int {
        transcriptionDiscardCountValue
    }

    func excludedAppBlockCount() -> Int {
        excludedAppBlockCountValue
    }

    func insertionAttemptCount() -> Int {
        insertionAttemptCountValue
    }

    func modelLoadCount() -> Int {
        modelLoadCountValue
    }

    func voiceCleaningCount() -> Int {
        voiceCleaningCountValue
    }

    func runtimeFailures() -> [(stage: String, reasonCode: String)] {
        runtimeFailureValues
    }
}

private actor FakeRuntimePostProcessor: RuntimePostProcessing {
    private let processedText: String?
    private var processedRawTextsValue: [String] = []

    func processedRawTexts() -> [String] {
        processedRawTextsValue
    }

    init(processedText: String?) {
        self.processedText = processedText
    }

    func process(rawText: String, preferences: AppPreferences) async -> String {
        processedRawTextsValue.append(rawText)
        return processedText ?? rawText
    }
}

private final class FakeRuntimeClock: RuntimeClock, @unchecked Sendable {
    private struct SleepRequest {
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var nowMillisecondsValue = 0
    private var sleeps: [SleepRequest] = []

    func nowMilliseconds() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return nowMillisecondsValue
    }

    func sleep(milliseconds: Int) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            sleeps.append(SleepRequest(continuation: continuation))
            lock.unlock()
        }
    }

    func sleepCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return sleeps.count
    }

    func fireOldestSleep(nowMilliseconds: Int) {
        lock.lock()
        nowMillisecondsValue = nowMilliseconds
        let request = sleeps.removeFirst()
        lock.unlock()
        request.continuation.resume()
    }
}

private extension RuntimeActiveModel {
    static let fixture = RuntimeActiveModel(
        id: "ggml-small.en-q5_1",
        displayName: "Balanced - Whisper small.en",
        tier: "balanced",
        localModelPath: "/tmp/ggml-small.en-q5_1.bin",
        useGPU: true,
        threadCount: 1
    )

    static let alternateFixture = RuntimeActiveModel(
        id: "whisper-large-v2-q5_0",
        displayName: "Whisper large-v2 Q5_0",
        tier: "experimental",
        localModelPath: "/tmp/whisper-large-v2-q5_0.bin",
        useGPU: true,
        threadCount: 1
    )

    static let voiceCleanerFixture = RuntimeActiveModel(
        id: "mossformer2-se-fp16",
        displayName: "Voice Cleaning - MossFormer2 SE fp16",
        tier: "recommended",
        localModelPath: "/tmp/mossformer2-se-fp16",
        useGPU: true,
        threadCount: nil,
        engine: .mlxAudio,
        variant: MossFormer2VoiceCleaningVariant.fp16.rawValue,
        accelerator: .metalGPU,
        artifactLayout: .modelDirectory,
        runtimeParameters: .legacyEnglishWhisper,
        purpose: .voiceCleaning
    )

    static func fixtureWithMaximumAudioSeconds(_ maximumAudioSeconds: Int) -> RuntimeActiveModel {
        RuntimeActiveModel(
            id: fixture.id,
            displayName: fixture.displayName,
            tier: fixture.tier,
            localModelPath: fixture.localModelPath,
            useGPU: fixture.useGPU,
            threadCount: fixture.threadCount,
            engine: fixture.engine,
            variant: fixture.variant,
            accelerator: fixture.accelerator,
            artifactLayout: fixture.artifactLayout,
            runtimeParameters: RuntimeParameters(
                language: fixture.runtimeParameters.language,
                detectLanguage: fixture.runtimeParameters.detectLanguage,
                translate: fixture.runtimeParameters.translate,
                strategy: fixture.runtimeParameters.strategy,
                beamSize: fixture.runtimeParameters.beamSize,
                bestOf: fixture.runtimeParameters.bestOf,
                temperature: fixture.runtimeParameters.temperature,
                temperatureFallback: fixture.runtimeParameters.temperatureFallback,
                noContext: fixture.runtimeParameters.noContext,
                tokenTimestamps: fixture.runtimeParameters.tokenTimestamps,
                maxAudioSeconds: maximumAudioSeconds
            )
        )
    }
}

private extension InsertionTargetIdentity {
    static let fixture = InsertionTargetIdentity(
        processIdentifier: 42,
        bundleIdentifier: "com.example.Target"
    )
}
