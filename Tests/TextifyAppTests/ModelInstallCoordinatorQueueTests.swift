import Foundation
@testable import Textify
import TextifyModels
import XCTest

final class ModelInstallCoordinatorQueueTests: XCTestCase {
    @MainActor
    func testTransferLifecycleChangesRequestStorageInventoryRefresh() {
        let probe = ModelInventoryRefreshProbe()
        let coordinator = ModelInstallCoordinator(
            installOperation: { _, _ in },
            makeAttemptID: { UUID().uuidString },
            lifecycleDidChange: {
                probe.record()
            }
        )

        let queuedAttemptID = coordinator.start(modelID: "artifact-a")
        XCTAssertEqual(probe.count, 1)

        if let queuedAttemptID {
            coordinator.cancel(attemptID: queuedAttemptID)
        }
        XCTAssertEqual(probe.count, 2)
    }

    func testNetworkRecoveryFiresForInitialOnlinePathAndLaterOfflineToOnlineTransition() {
        var state = ModelTransferNetworkRecoveryState()

        XCTAssertTrue(state.receive(isSatisfied: true))
        XCTAssertFalse(state.receive(isSatisfied: true))
        XCTAssertFalse(state.receive(isSatisfied: false))
        XCTAssertTrue(state.receive(isSatisfied: true))
    }

    @MainActor
    func testCoordinatorExecutesAttemptsSeriallyInFIFOOrder() async throws {
        let gate = InstallExecutionGate()
        let ids = SequentialAttemptIDs(["attempt-1", "attempt-2"])
        let coordinator = ModelInstallCoordinator(
            installOperation: { artifactID, _ in
                await gate.begin(artifactID)
                await gate.waitUntilReleased(artifactID)
            },
            makeAttemptID: { ids.next() },
            nowISO8601: { "2026-07-24T10:00:00Z" }
        )

        let firstID = coordinator.start(
            modelID: "artifact-a",
            purpose: .transcription,
            action: .install
        )
        let secondID = coordinator.start(
            modelID: "artifact-b",
            purpose: .voiceCleaning,
            action: .reinstall
        )
        await waitUntilAsync {
            await gate.startedArtifacts().contains("artifact-a")
        }
        let initiallyStarted = await gate.startedArtifacts()

        XCTAssertEqual(firstID, "attempt-1")
        XCTAssertEqual(secondID, "attempt-2")
        XCTAssertEqual(initiallyStarted, ["artifact-a"])
        XCTAssertEqual(
            coordinator.attempts.map(\.state.phase),
            [.checkingSpace, .queued]
        )

        await gate.release("artifact-a")
        await waitUntilAsync {
            await gate.startedArtifacts().contains("artifact-b")
        }
        let startedAfterFirstCompletion = await gate.startedArtifacts()
        XCTAssertEqual(startedAfterFirstCompletion, ["artifact-a", "artifact-b"])

        await gate.release("artifact-b")
        await waitUntil { !coordinator.isActive }

        XCTAssertEqual(
            coordinator.attempts.map(\.state.phase),
            [.installed, .installed]
        )
    }

    @MainActor
    func testCancelTargetsQueuedAttemptWithoutInterruptingActiveAttempt() async throws {
        let gate = InstallExecutionGate()
        let ids = SequentialAttemptIDs(["attempt-1", "attempt-2"])
        let coordinator = ModelInstallCoordinator(
            installOperation: { artifactID, _ in
                await gate.begin(artifactID)
                await gate.waitUntilReleased(artifactID)
            },
            makeAttemptID: { ids.next() }
        )
        _ = coordinator.start(modelID: "artifact-a")
        _ = coordinator.start(modelID: "artifact-b")
        await waitUntilAsync {
            await gate.startedArtifacts().contains("artifact-a")
        }

        coordinator.cancel(attemptID: "attempt-2")
        let startedBeforeRelease = await gate.startedArtifacts()

        XCTAssertTrue(coordinator.isActive)
        XCTAssertEqual(
            coordinator.attempt(id: "attempt-1")?.state.phase,
            .checkingSpace
        )
        XCTAssertEqual(
            coordinator.attempt(id: "attempt-2")?.state.phase,
            .cancelled
        )
        XCTAssertEqual(startedBeforeRelease, ["artifact-a"])

        await gate.release("artifact-a")
        await waitUntil { !coordinator.isActive }
        let finalStarted = await gate.startedArtifacts()
        XCTAssertEqual(finalStarted, ["artifact-a"])
    }

    @MainActor
    func testRetryCreatesNewAttemptAtTailAfterWorkAuthorizedLater() async throws {
        let gate = InstallExecutionGate()
        let ids = SequentialAttemptIDs([
            "attempt-1",
            "attempt-2",
            "attempt-3",
        ])
        let coordinator = ModelInstallCoordinator(
            installOperation: { artifactID, _ in
                if artifactID == "artifact-a" {
                    throw QueueCoordinatorFixtureError.failed
                }
                await gate.begin(artifactID)
                await gate.waitUntilReleased(artifactID)
            },
            makeAttemptID: { ids.next() }
        )

        _ = coordinator.start(modelID: "artifact-a")
        await waitUntil {
            coordinator.attempt(id: "attempt-1")?.state.phase == .failed
        }
        _ = coordinator.start(modelID: "artifact-b")
        await waitUntilAsync {
            await gate.startedArtifacts().contains("artifact-b")
        }

        let retryID = coordinator.retry(attemptID: "attempt-1")
        let startedBeforeRetryRelease = await gate.startedArtifacts()

        XCTAssertEqual(retryID, "attempt-3")
        XCTAssertEqual(
            coordinator.attempts.map(\.id),
            ["attempt-1", "attempt-2", "attempt-3"]
        )
        XCTAssertEqual(
            coordinator.attempt(id: "attempt-3")?.retryOfAttemptID,
            "attempt-1"
        )
        XCTAssertEqual(
            coordinator.attempt(id: "attempt-3")?.state.phase,
            .queued
        )
        XCTAssertEqual(startedBeforeRetryRelease, ["artifact-b"])

        coordinator.cancel(attemptID: "attempt-3")
        await gate.release("artifact-b")
        await waitUntil { !coordinator.isActive }
    }

    @MainActor
    func testStorageFailureEndsAttemptAndLaterFIFOAndTailRetryProceed() async {
        let operation = FirstStorageFailureOperation()
        let ids = SequentialAttemptIDs([
            "attempt-1",
            "attempt-2",
            "attempt-3",
        ])
        let coordinator = ModelInstallCoordinator(
            installOperation: { artifactID, _ in
                try await operation.install(artifactID)
            },
            makeAttemptID: { ids.next() }
        )

        _ = coordinator.start(modelID: "artifact-a")
        _ = coordinator.start(modelID: "artifact-b")
        await waitUntil { !coordinator.isActive }

        let failure = ModelInstallError.insufficientDiskSpace(
            requiredBytes: 750_000_000,
            availableBytes: 100_000_000
        )
        XCTAssertEqual(
            coordinator.attempts.map(\.state.phase),
            [.failed, .installed]
        )
        XCTAssertEqual(
            coordinator.attempt(id: "attempt-1")?.state.message,
            failure.description
        )
        let firstPassStarted = await operation.startedArtifacts()
        XCTAssertEqual(
            firstPassStarted,
            ["artifact-a", "artifact-b"]
        )

        XCTAssertEqual(
            coordinator.retry(attemptID: "attempt-1"),
            "attempt-3"
        )
        await waitUntil { !coordinator.isActive }

        XCTAssertEqual(
            coordinator.attempts.map(\.state.phase),
            [.failed, .installed, .installed]
        )
        XCTAssertEqual(
            coordinator.attempt(id: "attempt-3")?.retryOfAttemptID,
            "attempt-1"
        )
        let allStarted = await operation.startedArtifacts()
        XCTAssertEqual(
            allStarted,
            ["artifact-a", "artifact-b", "artifact-a"]
        )
    }

    @MainActor
    func testWaitingHeadPersistsAndBlocksLaterFIFOAttemptUntilNetworkRecovers() async throws {
        let readiness = InstallReadinessProbe()
        let gate = InstallExecutionGate()
        let ids = SequentialAttemptIDs(["attempt-1", "attempt-2"])
        let coordinator = ModelInstallCoordinator(
            installOperation: { artifactID, _ in
                if await readiness.shouldWaitForNetwork(artifactID) {
                    throw ModelInstallCoordinatorError.networkUnavailable
                }
                await gate.begin(artifactID)
                await gate.waitUntilReleased(artifactID)
            },
            makeAttemptID: { ids.next() }
        )

        _ = coordinator.start(modelID: "artifact-a")
        _ = coordinator.start(modelID: "artifact-b")
        await waitUntil {
            coordinator.attempt(id: "attempt-1")?.state.phase
                == .waitingForNetwork
        }
        let startedWhileWaiting = await gate.startedArtifacts()

        XCTAssertEqual(
            coordinator.attempts.map(\.state.phase),
            [.waitingForNetwork, .queued]
        )
        XCTAssertEqual(startedWhileWaiting, [])

        await readiness.setNetworkAvailable(for: "artifact-a")
        coordinator.networkDidBecomeAvailable()
        await waitUntilAsync {
            await gate.startedArtifacts().contains("artifact-a")
        }
        let startedAfterResume = await gate.startedArtifacts()
        XCTAssertEqual(startedAfterResume, ["artifact-a"])

        await gate.release("artifact-a")
        await waitUntilAsync {
            await gate.startedArtifacts().contains("artifact-b")
        }
        await gate.release("artifact-b")
        await waitUntil { !coordinator.isActive }
    }

    @MainActor
    func testOfflineHeadRecoversAutomaticallyInFIFOOrderWithoutRetryStorms() async throws {
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-24T12:00:00Z")
        )
        let authority = TransferAuthorityProbe(
            steps: [
                .waitingForNetwork,
                .ready(checkedAt: now),
            ]
        )
        let gate = InstallExecutionGate()
        let ids = SequentialAttemptIDs(["attempt-1", "attempt-2"])
        let coordinator = ModelInstallCoordinator(
            installOperation: { artifactID, _ in
                await gate.begin(artifactID)
                await gate.waitUntilReleased(artifactID)
            },
            lastSuccessfulCatalogIntegrityCheckAt: {
                authority.lastSuccessfulCheckAt
            },
            integrityCheckOperation: { artifactID in
                authority.check(artifactID: artifactID)
            },
            makeAttemptID: { ids.next() },
            now: { now }
        )

        _ = coordinator.start(modelID: "artifact-a")
        _ = coordinator.start(modelID: "artifact-b")
        await waitUntil {
            coordinator.attempt(id: "attempt-1")?.state.phase
                == .waitingForNetwork
        }
        for _ in 0..<100 {
            await Task.yield()
        }

        XCTAssertEqual(authority.checkCount, 1)
        XCTAssertEqual(
            coordinator.attempts.map(\.state.phase),
            [.waitingForNetwork, .queued]
        )

        coordinator.networkDidBecomeAvailable()
        coordinator.networkDidBecomeAvailable()
        await waitUntilAsync {
            await gate.startedArtifacts().contains("artifact-a")
        }

        XCTAssertEqual(authority.checkCount, 2)
        XCTAssertEqual(coordinator.attempts.map(\.id), [
            "attempt-1",
            "attempt-2",
        ])

        await gate.release("artifact-a")
        await waitUntilAsync {
            await gate.startedArtifacts().contains("artifact-b")
        }
        XCTAssertEqual(authority.checkCount, 2)

        await gate.release("artifact-b")
        await waitUntil { !coordinator.isActive }
    }

    @MainActor
    func testCatalogCheckRetryKeepsOriginalAuthorizationAndCancelAvailable() async throws {
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-24T12:00:00Z")
        )
        let authority = TransferAuthorityProbe(
            steps: [
                .waitingForCatalogCheck,
                .ready(checkedAt: now),
            ]
        )
        let gate = InstallExecutionGate()
        let coordinator = ModelInstallCoordinator(
            installOperation: { artifactID, _ in
                await gate.begin(artifactID)
                await gate.waitUntilReleased(artifactID)
            },
            lastSuccessfulCatalogIntegrityCheckAt: {
                authority.lastSuccessfulCheckAt
            },
            integrityCheckOperation: { artifactID in
                authority.check(artifactID: artifactID)
            },
            makeAttemptID: { "attempt-1" },
            now: { now }
        )

        _ = coordinator.start(modelID: "artifact-a")
        await waitUntil {
            coordinator.attempt(id: "attempt-1")?.state.phase
                == .waitingForCatalogCheck
        }

        XCTAssertTrue(
            ModelInstallRowPresentation.offersCancel(
                for: try XCTUnwrap(
                    coordinator.attempt(id: "attempt-1")?.state
                )
            )
        )
        XCTAssertEqual(coordinator.retry(attemptID: "attempt-1"), "attempt-1")
        await waitUntilAsync {
            await gate.startedArtifacts().contains("artifact-a")
        }

        XCTAssertEqual(authority.checkCount, 2)
        XCTAssertEqual(coordinator.attempts.map(\.id), ["attempt-1"])

        await gate.release("artifact-a")
        await waitUntil { !coordinator.isActive }
    }

    @MainActor
    func testAcceptedCatalogRefreshWakesWaitingHeadWithoutNewAuthorization() async throws {
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-24T12:00:00Z")
        )
        let authority = TransferAuthorityProbe(
            steps: [.waitingForCatalogCheck]
        )
        let gate = InstallExecutionGate()
        let coordinator = ModelInstallCoordinator(
            installOperation: { artifactID, _ in
                await gate.begin(artifactID)
                await gate.waitUntilReleased(artifactID)
            },
            lastSuccessfulCatalogIntegrityCheckAt: {
                authority.lastSuccessfulCheckAt
            },
            integrityCheckOperation: { artifactID in
                authority.check(artifactID: artifactID)
            },
            makeAttemptID: { "attempt-1" },
            now: { now }
        )

        _ = coordinator.start(modelID: "artifact-a")
        await waitUntil {
            coordinator.attempt(id: "attempt-1")?.state.phase
                == .waitingForCatalogCheck
        }

        authority.acceptCatalog(at: now)
        coordinator.catalogIntegrityCheckDidSucceed()
        await waitUntilAsync {
            await gate.startedArtifacts().contains("artifact-a")
        }

        XCTAssertEqual(authority.checkCount, 1)
        XCTAssertEqual(coordinator.attempts.map(\.id), ["attempt-1"])

        await gate.release("artifact-a")
        await waitUntil { !coordinator.isActive }
    }

    @MainActor
    func testAcceptedCatalogRefreshAlsoWakesNetworkBlockedHead() async throws {
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-24T12:00:00Z")
        )
        let authority = TransferAuthorityProbe(
            steps: [.waitingForNetwork]
        )
        let gate = InstallExecutionGate()
        let coordinator = ModelInstallCoordinator(
            installOperation: { artifactID, _ in
                await gate.begin(artifactID)
                await gate.waitUntilReleased(artifactID)
            },
            lastSuccessfulCatalogIntegrityCheckAt: {
                authority.lastSuccessfulCheckAt
            },
            integrityCheckOperation: { artifactID in
                authority.check(artifactID: artifactID)
            },
            makeAttemptID: { "attempt-1" },
            now: { now }
        )

        _ = coordinator.start(modelID: "artifact-a")
        await waitUntil {
            coordinator.attempt(id: "attempt-1")?.state.phase
                == .waitingForNetwork
        }

        authority.acceptCatalog(at: now)
        coordinator.catalogIntegrityCheckDidSucceed()
        await waitUntilAsync {
            await gate.startedArtifacts().contains("artifact-a")
        }

        XCTAssertEqual(authority.checkCount, 1)
        XCTAssertEqual(coordinator.attempts.map(\.id), ["attempt-1"])

        await gate.release("artifact-a")
        await waitUntil { !coordinator.isActive }
    }

    @MainActor
    func testPersistedResumeRequiresFreshIntegrityCheckBeforeTransferStarts() async throws {
        let directory = temporaryDirectory()
        defer {
            if FileManager.default.fileExists(atPath: directory.path) {
                try? FileManager.default.removeItem(at: directory)
            }
        }
        let store = ModelInstallQueueStore(
            fileURL: directory.appendingPathComponent("install-queue.json")
        )
        var queue = ModelInstallQueue()
        _ = try queue.authorize(
            artifactID: "artifact-a",
            purpose: .transcription,
            action: .install,
            attemptID: "attempt-1",
            createdAt: "2026-07-23T20:00:00Z"
        )
        try queue.transition(
            attemptID: "attempt-1",
            to: DownloadState(
                modelID: "artifact-a",
                phase: .checkingSpace
            )
        )
        try queue.transition(
            attemptID: "attempt-1",
            to: DownloadState(
                modelID: "artifact-a",
                phase: .downloading,
                bytesDownloaded: 50,
                totalBytes: 100
            )
        )
        try store.save(queue)

        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-24T12:00:00Z")
        )
        let stale = now.addingTimeInterval(-12 * 60 * 60 - 1)
        let authority = TransferAuthorityProbe(
            lastSuccessfulCheckAt: stale,
            steps: [.ready(checkedAt: now)]
        )
        let gate = InstallExecutionGate()
        let coordinator = ModelInstallCoordinator(
            queueStore: store,
            installOperation: { artifactID, _ in
                await gate.begin(artifactID)
                await gate.waitUntilReleased(artifactID)
            },
            lastSuccessfulCatalogIntegrityCheckAt: {
                authority.lastSuccessfulCheckAt
            },
            integrityCheckOperation: { artifactID in
                authority.check(artifactID: artifactID)
            },
            now: { now }
        )

        await waitUntilAsync {
            await gate.startedArtifacts().contains("artifact-a")
        }

        XCTAssertEqual(authority.checkCount, 1)
        XCTAssertEqual(
            coordinator.attempt(id: "attempt-1")?.state.bytesDownloaded,
            50
        )

        await gate.release("artifact-a")
        await waitUntil { !coordinator.isActive }
    }

    @MainActor
    func testKnownRevocationOverridesFreshCachedAuthorityBeforeInstallStarts() async throws {
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-24T12:00:00Z")
        )
        let authority = TransferAuthorityProbe(
            lastSuccessfulCheckAt: now,
            steps: []
        )
        let gate = InstallExecutionGate()
        let coordinator = ModelInstallCoordinator(
            installOperation: { artifactID, _ in
                await gate.begin(artifactID)
            },
            lastSuccessfulCatalogIntegrityCheckAt: {
                authority.lastSuccessfulCheckAt
            },
            integrityCheckOperation: { artifactID in
                authority.check(artifactID: artifactID)
            },
            isArtifactKnownRevoked: { artifactID, _ in
                artifactID == "artifact-a"
            },
            makeAttemptID: { "attempt-1" },
            now: { now }
        )

        let attemptID = coordinator.start(modelID: "artifact-a")
        await Task.yield()

        XCTAssertNil(attemptID)
        XCTAssertEqual(coordinator.attempts, [])
        XCTAssertEqual(authority.checkCount, 0)
        let startedArtifacts = await gate.startedArtifacts()
        XCTAssertEqual(startedArtifacts, [])
    }

    @MainActor
    func testPersistedArtifactDigestStopsAttemptAfterCatalogOmission() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ModelInstallQueueStore(
            fileURL: directory.appendingPathComponent("install-queue.json")
        )
        let digest = ModelRevocationDigestTarget(
            algorithm: .sha256,
            value: String(repeating: "a", count: 64),
            scope: .singleFilePayload
        )
        let identity = ModelInstallArtifactIdentity(
            artifactID: "artifact-a",
            contentDigests: [digest]
        )
        let revocations = KnownDigestRevocationProbe()
        let gate = InstallExecutionGate()
        let coordinator = ModelInstallCoordinator(
            queueStore: store,
            installOperation: { artifactID, _ in
                await gate.begin(artifactID)
                try await Task.sleep(nanoseconds: .max)
            },
            artifactIdentityProvider: { _ in identity },
            isArtifactKnownRevoked: { _, authorizedIdentity in
                revocations.contains(authorizedIdentity)
            },
            makeAttemptID: { "attempt-1" }
        )

        _ = coordinator.start(modelID: "artifact-a")
        await waitUntilAsync {
            await gate.startedArtifacts().contains("artifact-a")
        }
        revocations.revoke(digest)
        coordinator.enforceKnownRevocations()
        await waitUntil {
            coordinator.attempt(id: "attempt-1")?.state.phase
                == .revoked
        }

        XCTAssertEqual(
            coordinator.attempt(id: "attempt-1")?
                .authorizedArtifactIdentity,
            identity
        )
        XCTAssertEqual(
            try store.load().attempt(id: "attempt-1")?
                .authorizedArtifactIdentity,
            identity
        )
    }

    @MainActor
    func testRelaunchDiscoversRetainedStagingAfterDigestRevocationAndCatalogOmission() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let layout = ModelStorageLayout(rootDirectory: directory)
        let store = ModelInstallQueueStore(
            fileURL: layout.installQueueURL
        )
        let expectedFile = ModelFile(
            filename: "model.bin",
            url: "https://models.textify.example/model.bin",
            sha256: String(repeating: "a", count: 64),
            sizeBytes: 4
        )
        let identity = ModelInstallArtifactIdentity(
            artifactID: "artifact-a",
            contentDigests: [
                ModelRevocationDigestTarget(
                    algorithm: .sha256,
                    value: expectedFile.sha256,
                    scope: .singleFilePayload
                ),
            ],
            expectedFiles: [expectedFile]
        )
        var queue = ModelInstallQueue()
        _ = try queue.authorize(
            artifactID: "artifact-a",
            authorizedArtifactIdentity: identity,
            purpose: .transcription,
            action: .install,
            attemptID: "attempt-1",
            createdAt: "2026-07-24T10:00:00Z"
        )
        try queue.transition(
            attemptID: "attempt-1",
            to: DownloadState(
                modelID: "artifact-a",
                phase: .checkingSpace
            )
        )
        try store.save(queue)
        let stagingDirectory = layout.downloadsDirectory
            .appendingPathComponent(
                ".artifact-a.installing-crash",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )
        try Data("data".utf8).write(
            to: stagingDirectory.appendingPathComponent("model.bin")
        )
        let started = InstallStartProbe()

        let coordinator = ModelInstallCoordinator(
            queueStore: store,
            installOperation: { artifactID, _ in
                await started.record(artifactID)
            },
            resumableDataProvider: { attempt in
                guard let expectedFiles =
                    attempt.authorizedArtifactIdentity?.expectedFiles
                else {
                    return nil
                }
                return try? ModelInstallResumableDataInspector(
                    layout: layout
                ).inspect(
                    for: attempt,
                    expectedFiles: expectedFiles
                )
            },
            isArtifactKnownRevoked: { _, authorizedIdentity in
                authorizedIdentity?.contentDigests.contains(
                    identity.contentDigests[0]
                ) == true
            }
        )
        await waitUntil {
            coordinator.attempt(id: "attempt-1")?
                .resumableData?.validatedBytes == 4
        }

        XCTAssertEqual(
            coordinator.attempt(id: "attempt-1")?.state.phase,
            .revoked
        )
        let startedArtifacts = await started.values()
        XCTAssertEqual(startedArtifacts, [])
        XCTAssertEqual(
            try store.load().attempt(id: "attempt-1")?
                .resumableData?.validatedBytes,
            4
        )
    }

    @MainActor
    func testAcceptedRevocationStopsActiveAndQueuedAttemptsThenRunsUnaffectedTail() async {
        let started = InstallStartProbe()
        let revocations = KnownRevocationProbe()
        let ids = SequentialAttemptIDs([
            "attempt-1",
            "attempt-2",
            "attempt-3",
        ])
        let coordinator = ModelInstallCoordinator(
            installOperation: { artifactID, _ in
                await started.record(artifactID)
                if artifactID == "artifact-a" {
                    try await Task.sleep(nanoseconds: .max)
                }
            },
            resumableDataProvider: { attempt in
                guard attempt.artifactID == "artifact-a" else {
                    return nil
                }
                return ModelInstallResumableData(
                    sourceAttemptID: attempt.id,
                    associatedAttemptID: attempt.id,
                    validatedBytes: 256,
                    fileCount: 1
                )
            },
            isArtifactKnownRevoked: { artifactID, _ in
                revocations.contains(artifactID)
            },
            makeAttemptID: { ids.next() }
        )
        _ = coordinator.start(modelID: "artifact-a")
        _ = coordinator.start(modelID: "artifact-b")
        _ = coordinator.start(modelID: "artifact-c")
        await waitUntilAsync {
            await started.values().contains("artifact-a")
        }

        revocations.replace(with: ["artifact-a", "artifact-b"])
        coordinator.enforceKnownRevocations()
        await waitUntil {
            coordinator.attempt(id: "attempt-3")?.state.phase == .installed
        }

        XCTAssertEqual(
            coordinator.attempts.map(\.state.phase),
            [.revoked, .revoked, .installed]
        )
        XCTAssertEqual(
            coordinator.attempt(id: "attempt-1")?
                .resumableData?.validatedBytes,
            256
        )
        XCTAssertNil(coordinator.retry(attemptID: "attempt-1"))
        coordinator.removeRetainedData(attemptID: "attempt-1")
        XCTAssertNil(
            coordinator.attempt(id: "attempt-1")?.resumableData
        )
        let startedArtifacts = await started.values()
        XCTAssertEqual(
            startedArtifacts,
            ["artifact-a", "artifact-c"]
        )
    }

    @MainActor
    func testRetainedDataIsNotDeletedWhenQueuePersistenceFails() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ModelInstallQueueStore(
            fileURL: directory.appendingPathComponent("install-queue.json")
        )
        let retainedData = ModelInstallResumableData(
            sourceAttemptID: "attempt-1",
            associatedAttemptID: "attempt-1",
            validatedBytes: 256,
            fileCount: 1,
            filenames: ["model.bin"]
        )
        let queue = ModelInstallQueue(
            attempts: [
                ModelInstallQueueAttempt(
                    id: "attempt-1",
                    artifactID: "artifact-a",
                    purpose: .transcription,
                    action: .install,
                    createdAt: "2026-07-24T10:00:00Z",
                    state: DownloadState(
                        modelID: "artifact-a",
                        phase: .revoked
                    ),
                    resumableData: retainedData
                ),
            ]
        )
        try store.save(queue)
        let saveProbe = QueueSaveProbe(store: store)
        let removalProbe = RetainedDataRemovalProbe()
        let coordinator = ModelInstallCoordinator(
            queueStore: store,
            queueSaveOperation: { queue in
                try saveProbe.save(queue)
            },
            installOperation: { _, _ in },
            removeRetainedDataOperation: { attempt in
                removalProbe.record(attempt.id)
            }
        )
        saveProbe.shouldFail = true

        coordinator.removeRetainedData(attemptID: "attempt-1")

        XCTAssertEqual(removalProbe.attemptIDs, [])
        XCTAssertEqual(
            coordinator.attempt(id: "attempt-1")?.resumableData,
            retainedData
        )
        XCTAssertEqual(
            try store.load().attempt(id: "attempt-1")?.resumableData,
            retainedData
        )
        XCTAssertEqual(
            coordinator.persistenceErrorMessage,
            "Textify could not save the Downloads queue."
        )
    }

    @MainActor
    func testRetainedDataRemovalDeletesUnionForSameArtifactAttempts() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ModelInstallQueueStore(
            fileURL: directory.appendingPathComponent("install-queue.json")
        )
        let queue = ModelInstallQueue(
            attempts: [
                ModelInstallQueueAttempt(
                    id: "attempt-1",
                    artifactID: "artifact-a",
                    purpose: .transcription,
                    action: .install,
                    createdAt: "2026-07-24T10:00:00Z",
                    state: DownloadState(
                        modelID: "artifact-a",
                        phase: .revoked
                    ),
                    resumableData: ModelInstallResumableData(
                        sourceAttemptID: "attempt-1",
                        associatedAttemptID: "attempt-1",
                        validatedBytes: 256,
                        fileCount: 1,
                        filenames: ["old-model.bin"]
                    )
                ),
                ModelInstallQueueAttempt(
                    id: "attempt-2",
                    artifactID: "artifact-a",
                    purpose: .transcription,
                    action: .reinstall,
                    createdAt: "2026-07-24T11:00:00Z",
                    state: DownloadState(
                        modelID: "artifact-a",
                        phase: .revoked
                    ),
                    resumableData: ModelInstallResumableData(
                        sourceAttemptID: "attempt-2",
                        associatedAttemptID: "attempt-2",
                        validatedBytes: 512,
                        fileCount: 1,
                        filenames: ["new-model.bin"]
                    )
                ),
            ]
        )
        try store.save(queue)
        let removalProbe = RetainedDataRemovalProbe()
        let coordinator = ModelInstallCoordinator(
            queueStore: store,
            installOperation: { _, _ in },
            removeRetainedDataOperation: { attempt in
                removalProbe.record(attempt.id)
            }
        )

        coordinator.removeRetainedData(attemptID: "attempt-1")

        XCTAssertEqual(
            removalProbe.attemptIDs,
            ["attempt-1", "attempt-2"]
        )
        XCTAssertNil(
            coordinator.attempt(id: "attempt-1")?.resumableData
        )
        XCTAssertNil(
            coordinator.attempt(id: "attempt-2")?.resumableData
        )
        XCTAssertTrue(
            try store.load().attempts.allSatisfy {
                $0.resumableData == nil
            }
        )
    }

    @MainActor
    func testCancellingFreshRestoredInstallPreservesIsolatedRevokedBytes() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let layout = ModelStorageLayout(rootDirectory: directory)
        try FileManager.default.createDirectory(
            at: layout.downloadsDirectory,
            withIntermediateDirectories: true
        )
        let partialURL = try layout.temporaryDownloadURL(
            modelID: "artifact-a",
            filename: "model.bin"
        )
        let metadataURL = try layout.downloadResumeMetadataURL(
            modelID: "artifact-a",
            filename: "model.bin"
        )
        try Data("retained partial".utf8).write(to: partialURL)
        try Data("retained metadata".utf8).write(to: metadataURL)
        let oldStaging = layout.downloadsDirectory.appendingPathComponent(
            ".artifact-a.installing-old",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: oldStaging,
            withIntermediateDirectories: true
        )
        try Data("staged model".utf8).write(
            to: oldStaging.appendingPathComponent("model.bin")
        )
        let store = ModelInstallQueueStore(
            fileURL: layout.installQueueURL
        )
        let retainedData = ModelInstallResumableData(
            sourceAttemptID: "attempt-1",
            associatedAttemptID: "attempt-1",
            validatedBytes: 16,
            fileCount: 1,
            filenames: ["model.bin"]
        )
        let queue = ModelInstallQueue(
            attempts: [
                ModelInstallQueueAttempt(
                    id: "attempt-1",
                    artifactID: "artifact-a",
                    purpose: .transcription,
                    action: .install,
                    createdAt: "2026-07-24T10:00:00Z",
                    state: DownloadState(
                        modelID: "artifact-a",
                        phase: .revoked
                    ),
                    resumableData: retainedData
                ),
            ]
        )
        try store.save(queue)
        let started = InstallStartProbe()
        let remover = ModelInstallRetainedDataRemover(layout: layout)
        let isolator = ModelInstallRetainedDataIsolator(layout: layout)
        let coordinator = ModelInstallCoordinator(
            queueStore: store,
            installOperation: { artifactID, _ in
                await started.record(artifactID)
                try await Task.sleep(nanoseconds: .max)
            },
            removeStagingDataOperation: { attempt in
                try remover.removeDirectoryStaging(
                    modelID: attempt.artifactID
                )
            },
            isolateRetainedDataOperation: { attempts in
                try isolator.isolate(
                    modelID: "artifact-a",
                    filenames: attempts.flatMap {
                        $0.resumableData?.filenames ?? []
                    }
                )
            },
            makeAttemptID: { "attempt-2" }
        )

        XCTAssertEqual(
            coordinator.start(
                modelID: "artifact-a",
                action: .reinstall
            ),
            "attempt-2"
        )
        await waitUntilAsync {
            await started.values().contains("artifact-a")
        }
        let liveStaging = layout.downloadsDirectory.appendingPathComponent(
            ".artifact-a.installing-live",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: liveStaging,
            withIntermediateDirectories: true
        )
        try Data("live model".utf8).write(
            to: liveStaging.appendingPathComponent("model.bin")
        )

        XCTAssertNil(
            coordinator.start(
                modelID: "artifact-a",
                action: .reinstall
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: liveStaging.path)
        )
        coordinator.removeRetainedData(attemptID: "attempt-1")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: liveStaging.path)
        )
        XCTAssertEqual(
            coordinator.attempt(id: "attempt-1")?.resumableData,
            retainedData
        )

        coordinator.cancel(attemptID: "attempt-2")
        await waitUntil {
            coordinator.attempt(id: "attempt-2")?.state.phase
                == .cancelled
        }

        let retainedArchives =
            try FileManager.default.contentsOfDirectory(
                at: layout.downloadsDirectory,
                includingPropertiesForKeys: nil
            ).filter {
                $0.lastPathComponent.hasPrefix(
                    ".artifact-a.retained-"
                )
            }
        let partialArchive = try XCTUnwrap(
            retainedArchives.first {
                FileManager.default.fileExists(
                    atPath: $0.appendingPathComponent(
                        partialURL.lastPathComponent
                    ).path
                )
            }
        )
        let stagingArchive = try XCTUnwrap(
            retainedArchives.first {
                FileManager.default.fileExists(
                    atPath: $0.appendingPathComponent("model.bin").path
                )
            }
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: partialArchive.appendingPathComponent(
                    partialURL.lastPathComponent
                ).path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: stagingArchive.appendingPathComponent(
                    "model.bin"
                ).path
            )
        )
        XCTAssertEqual(
            coordinator.attempt(id: "attempt-1")?.resumableData,
            retainedData
        )
    }

    @MainActor
    func testRelaunchTerminatesEveryKnownRevokedAttemptWithoutStartingInstall() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ModelInstallQueueStore(
            fileURL: directory.appendingPathComponent("install-queue.json")
        )
        var queue = ModelInstallQueue()
        _ = try queue.authorize(
            artifactID: "artifact-a",
            purpose: .transcription,
            action: .install,
            attemptID: "attempt-1",
            createdAt: "2026-07-24T10:00:00Z"
        )
        try queue.transition(
            attemptID: "attempt-1",
            to: DownloadState(
                modelID: "artifact-a",
                phase: .checkingSpace
            )
        )
        _ = try queue.authorize(
            artifactID: "artifact-b",
            purpose: .voiceCleaning,
            action: .install,
            attemptID: "attempt-2",
            createdAt: "2026-07-24T10:01:00Z"
        )
        _ = try queue.authorize(
            artifactID: "artifact-c",
            purpose: .transcription,
            action: .install,
            attemptID: "attempt-3",
            createdAt: "2026-07-24T10:02:00Z"
        )
        try queue.transition(
            attemptID: "attempt-3",
            to: DownloadState(
                modelID: "artifact-c",
                phase: .revoked
            )
        )
        try store.save(queue)
        let started = InstallStartProbe()

        let coordinator = ModelInstallCoordinator(
            queueStore: store,
            installOperation: { artifactID, _ in
                await started.record(artifactID)
            },
            resumableDataProvider: { attempt in
                ModelInstallResumableData(
                    sourceAttemptID: attempt.id,
                    associatedAttemptID: attempt.id,
                    validatedBytes: 128,
                    fileCount: 1,
                    filenames: ["model.bin"]
                )
            },
            isArtifactKnownRevoked: { artifactID, _ in
                ["artifact-a", "artifact-b"].contains(artifactID)
            }
        )
        await waitUntil {
            coordinator.attempts.allSatisfy {
                $0.state.phase == .revoked
            }
        }

        let startedArtifacts = await started.values()
        XCTAssertEqual(startedArtifacts, [])
        XCTAssertEqual(
            try store.load().attempts.map(\.state.phase),
            [.revoked, .revoked, .revoked]
        )
        XCTAssertEqual(
            try store.load().attempts.map {
                $0.resumableData?.validatedBytes
            },
            [128, 128, 128]
        )
    }

    @MainActor
    func testCoordinatorLoadsDurableQueueAndResumesHeadAfterRelaunch() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ModelInstallQueueStore(
            fileURL: directory.appendingPathComponent("install-queue.json")
        )
        var queue = ModelInstallQueue()
        _ = try queue.authorize(
            artifactID: "artifact-a",
            purpose: .transcription,
            action: .install,
            attemptID: "attempt-1",
            createdAt: "2026-07-24T10:00:00Z"
        )
        try queue.transition(
            attemptID: "attempt-1",
            to: DownloadState(
                modelID: "artifact-a",
                phase: .checkingSpace
            )
        )
        _ = try queue.authorize(
            artifactID: "artifact-b",
            purpose: .voiceCleaning,
            action: .install,
            attemptID: "attempt-2",
            createdAt: "2026-07-24T10:01:00Z"
        )
        try store.save(queue)

        let gate = InstallExecutionGate()
        let coordinator = ModelInstallCoordinator(
            queueStore: store,
            installOperation: { artifactID, _ in
                await gate.begin(artifactID)
                await gate.waitUntilReleased(artifactID)
            }
        )
        await waitUntilAsync {
            await gate.startedArtifacts().contains("artifact-a")
        }
        let startedAfterRelaunch = await gate.startedArtifacts()

        XCTAssertEqual(
            coordinator.attempts.map(\.id),
            ["attempt-1", "attempt-2"]
        )
        XCTAssertEqual(startedAfterRelaunch, ["artifact-a"])

        await gate.release("artifact-a")
        await waitUntilAsync {
            await gate.startedArtifacts().contains("artifact-b")
        }
        await gate.release("artifact-b")
        await waitUntil { !coordinator.isActive }

        let persisted = try store.load()
        XCTAssertEqual(
            persisted.attempts.map(\.state.phase),
            [.installed, .installed]
        )
    }

    @MainActor
    func testProgressProjectionCarriesAttemptIdentityPerArtifact() async throws {
        let gate = InstallExecutionGate()
        let ids = SequentialAttemptIDs(["attempt-1", "attempt-2"])
        let coordinator = ModelInstallCoordinator(
            installOperation: { artifactID, onStateChange in
                onStateChange(
                    DownloadState(
                        modelID: artifactID,
                        phase: .downloading,
                        bytesDownloaded: 25,
                        totalBytes: 100
                    )
                )
                await gate.begin(artifactID)
                await gate.waitUntilReleased(artifactID)
            },
            makeAttemptID: { ids.next() }
        )

        _ = coordinator.start(modelID: "artifact-a")
        _ = coordinator.start(modelID: "artifact-b")
        await waitUntilAsync {
            await gate.startedArtifacts().contains("artifact-a")
        }
        await waitUntil {
            coordinator.artifactStates["artifact-a"]?.phase == .downloading
        }

        XCTAssertEqual(
            coordinator.artifactStates["artifact-a"]?.attemptID,
            "attempt-1"
        )
        XCTAssertEqual(
            coordinator.artifactStates["artifact-b"]?.phase,
            .queued
        )
        XCTAssertNil(coordinator.artifactStates["artifact-c"])

        coordinator.cancel(attemptID: "attempt-2")
        await gate.release("artifact-a")
        await waitUntil { !coordinator.isActive }
    }

    @MainActor
    func testPersistenceFailureRollsBackCancelAndStopsFurtherQueueMutation() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let queueURL = directory.appendingPathComponent("install-queue.json")
        let gate = InstallExecutionGate()
        let coordinator = ModelInstallCoordinator(
            queueStore: ModelInstallQueueStore(fileURL: queueURL),
            installOperation: { artifactID, _ in
                await gate.begin(artifactID)
                await gate.waitUntilReleased(artifactID)
            },
            makeAttemptID: { "attempt-1" }
        )
        _ = coordinator.start(modelID: "artifact-a")
        await waitUntilAsync {
            await gate.startedArtifacts().contains("artifact-a")
        }

        try FileManager.default.removeItem(at: queueURL)
        try FileManager.default.createDirectory(
            at: queueURL,
            withIntermediateDirectories: false
        )
        coordinator.cancel(attemptID: "attempt-1")

        XCTAssertEqual(
            coordinator.attempt(id: "attempt-1")?.state.phase,
            .checkingSpace
        )
        XCTAssertTrue(coordinator.isActive)
        XCTAssertEqual(
            coordinator.persistenceErrorMessage,
            "Textify could not save the Downloads queue."
        )
        XCTAssertNil(coordinator.start(modelID: "artifact-b"))
        XCTAssertEqual(coordinator.attempts.map(\.id), ["attempt-1"])

        await gate.release("artifact-a")
        await waitUntil { !coordinator.isActive }
    }

    @MainActor
    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<2_000 {
            if predicate() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for coordinator state.")
    }

    private func waitUntilAsync(
        _ predicate: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0..<2_000 {
            if await predicate() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for asynchronous test state.")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TextifyModelInstallCoordinatorTests-\(UUID().uuidString)",
                isDirectory: true
            )
    }
}

@MainActor
private final class ModelInventoryRefreshProbe {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

@MainActor
private final class QueueSaveProbe {
    let store: ModelInstallQueueStore
    var shouldFail = false

    init(store: ModelInstallQueueStore) {
        self.store = store
    }

    func save(_ queue: ModelInstallQueue) throws {
        if shouldFail {
            throw QueueCoordinatorFixtureError.failed
        }
        try store.save(queue)
    }
}

@MainActor
private final class RetainedDataRemovalProbe {
    private(set) var attemptIDs: [String] = []

    func record(_ attemptID: String) {
        attemptIDs.append(attemptID)
    }
}

private enum QueueCoordinatorFixtureError: Error {
    case failed
}

private final class SequentialAttemptIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String]

    init(_ values: [String]) {
        self.values = values
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        return values.removeFirst()
    }
}

private actor InstallExecutionGate {
    private var started: [String] = []
    private var released: Set<String> = []
    private var releaseWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func begin(_ artifactID: String) {
        started.append(artifactID)
    }

    func waitUntilReleased(_ artifactID: String) async {
        guard !released.contains(artifactID) else {
            return
        }
        await withCheckedContinuation { continuation in
            releaseWaiters[artifactID, default: []].append(continuation)
        }
    }

    func release(_ artifactID: String) {
        released.insert(artifactID)
        let waiters = releaseWaiters.removeValue(forKey: artifactID) ?? []
        for waiter in waiters {
            waiter.resume()
        }
    }

    func startedArtifacts() -> [String] {
        started
    }
}

private actor InstallStartProbe {
    private var started: [String] = []

    func record(_ artifactID: String) {
        started.append(artifactID)
    }

    func values() -> [String] {
        started
    }
}

@MainActor
private final class KnownRevocationProbe {
    private var artifactIDs = Set<String>()

    func contains(_ artifactID: String) -> Bool {
        artifactIDs.contains(artifactID)
    }

    func replace(with artifactIDs: Set<String>) {
        self.artifactIDs = artifactIDs
    }
}

@MainActor
private final class KnownDigestRevocationProbe {
    private var digest: ModelRevocationDigestTarget?

    func contains(
        _ identity: ModelInstallArtifactIdentity?
    ) -> Bool {
        guard let digest else {
            return false
        }
        return identity?.contentDigests.contains(digest) == true
    }

    func revoke(_ digest: ModelRevocationDigestTarget) {
        self.digest = digest
    }
}

private actor InstallReadinessProbe {
    private var waitingArtifacts: Set<String> = ["artifact-a"]

    func shouldWaitForNetwork(_ artifactID: String) -> Bool {
        waitingArtifacts.contains(artifactID)
    }

    func setNetworkAvailable(for artifactID: String) {
        waitingArtifacts.remove(artifactID)
    }
}

private actor FirstStorageFailureOperation {
    private var started: [String] = []
    private var didFailFirstArtifact = false

    func install(_ artifactID: String) throws {
        started.append(artifactID)
        if artifactID == "artifact-a", !didFailFirstArtifact {
            didFailFirstArtifact = true
            throw ModelInstallError.insufficientDiskSpace(
                requiredBytes: 750_000_000,
                availableBytes: 100_000_000
            )
        }
    }

    func startedArtifacts() -> [String] {
        started
    }
}

private final class TransferAuthorityProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [ModelTransferPrerequisiteResult]
    private var storedLastSuccessfulCheckAt: Date?
    private var storedCheckCount = 0

    init(
        lastSuccessfulCheckAt: Date? = nil,
        steps: [ModelTransferPrerequisiteResult]
    ) {
        storedLastSuccessfulCheckAt = lastSuccessfulCheckAt
        self.steps = steps
    }

    var lastSuccessfulCheckAt: Date? {
        lock.withLock {
            storedLastSuccessfulCheckAt
        }
    }

    var checkCount: Int {
        lock.withLock {
            storedCheckCount
        }
    }

    func check(artifactID: String) -> ModelTransferPrerequisiteResult {
        lock.withLock {
            storedCheckCount += 1
            guard !steps.isEmpty else {
                return .waitingForCatalogCheck
            }
            let next = steps.removeFirst()
            if case let .ready(checkedAt) = next {
                storedLastSuccessfulCheckAt = checkedAt
            }
            return next
        }
    }

    func acceptCatalog(at date: Date) {
        lock.withLock {
            storedLastSuccessfulCheckAt = date
        }
    }
}
