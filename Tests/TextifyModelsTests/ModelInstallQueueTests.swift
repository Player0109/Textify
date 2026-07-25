import Foundation
import TextifyModels
import XCTest

final class ModelInstallQueueTests: XCTestCase {
    func testQueueStoreReportsAuthorizationAndStartedPersistence() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = ModelWorkflowBoundaryRecorder()
        let store = ModelInstallQueueStore(
            fileURL: root.appendingPathComponent("queue.json"),
            durabilityObserver: recorder.observer
        )
        var queue = ModelInstallQueue()
        try queue.authorize(
            artifactID: "artifact-a",
            purpose: .transcription,
            action: .install,
            attemptID: "attempt-a",
            createdAt: "2026-07-25T00:00:00Z"
        )
        try store.save(queue)
        try queue.transition(
            attemptID: "attempt-a",
            to: DownloadState(
                modelID: "artifact-a",
                phase: .checkingSpace,
                message: "Checking space",
                attemptID: "attempt-a"
            )
        )
        try store.save(queue)

        XCTAssertEqual(
            recorder.events,
            [
                ModelWorkflowBoundaryEvent(
                    boundary: .queueAuthorizationPersisted,
                    artifactID: "artifact-a"
                ),
                ModelWorkflowBoundaryEvent(
                    boundary: .queueAttemptStartedPersisted,
                    artifactID: "artifact-a"
                ),
            ]
        )
    }

    func testTransferFreshnessIncludesExactTwelveHourBoundaryAndRejectsFutureClockValues() throws {
        let policy = ModelTransferFreshnessPolicy()
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-24T12:00:00Z")
        )

        XCTAssertTrue(
            policy.isFresh(
                lastSuccessfulCheckAt: now.addingTimeInterval(-12 * 60 * 60),
                now: now
            )
        )
        XCTAssertFalse(
            policy.isFresh(
                lastSuccessfulCheckAt: now.addingTimeInterval(-12 * 60 * 60 - 0.001),
                now: now
            )
        )
        XCTAssertFalse(
            policy.isFresh(
                lastSuccessfulCheckAt: now.addingTimeInterval(1),
                now: now
            )
        )
        XCTAssertFalse(
            policy.isFresh(lastSuccessfulCheckAt: nil, now: now)
        )
    }

    func testAuthorizationsAppendImmutableAttemptsInFIFOOrder() throws {
        var ids = ["attempt-1", "attempt-2"].makeIterator()
        var queue = ModelInstallQueue()

        let first = try queue.authorize(
            artifactID: "artifact-a",
            purpose: .transcription,
            action: .install,
            attemptID: ids.next()!,
            createdAt: "2026-07-24T10:00:00Z"
        )
        let second = try queue.authorize(
            artifactID: "artifact-b",
            purpose: .voiceCleaning,
            action: .reinstall,
            attemptID: ids.next()!,
            createdAt: "2026-07-24T10:01:00Z"
        )

        XCTAssertEqual(queue.attempts.map(\.id), ["attempt-1", "attempt-2"])
        XCTAssertEqual(queue.attempts.map(\.artifactID), ["artifact-a", "artifact-b"])
        XCTAssertEqual(queue.attempts.map(\.action), [.install, .reinstall])
        XCTAssertEqual(first.state.phase, .queued)
        XCTAssertEqual(second.state.phase, .queued)
        XCTAssertEqual(queue.headAttempt?.id, first.id)
    }

    func testOnlyFIFOHeadCanEnterPipelineAndWaitingHeadBlocksLaterAttempt() throws {
        var queue = try twoAttemptQueue()

        XCTAssertThrowsError(
            try queue.transition(
                attemptID: "attempt-2",
                to: DownloadState(
                    modelID: "artifact-b",
                    phase: .checkingSpace
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ModelInstallQueueError,
                .attemptIsNotFIFOHead("attempt-2")
            )
        }

        try queue.transition(
            attemptID: "attempt-1",
            to: DownloadState(
                modelID: "artifact-a",
                phase: .waitingForNetwork
            )
        )

        XCTAssertEqual(queue.headAttempt?.id, "attempt-1")
        XCTAssertNil(queue.nextRunnableAttempt)
        XCTAssertEqual(queue.attempt(id: "attempt-2")?.state.phase, .queued)
    }

    func testDeclaredTransitionMatrixAcceptsEveryAllowedEdgeAndRejectsEveryForbiddenEdge() throws {
        for source in DownloadPhase.allCases {
            for destination in DownloadPhase.allCases {
                var queue = ModelInstallQueue(
                    attempts: [
                        ModelInstallQueueAttempt(
                            id: "attempt",
                            artifactID: "artifact",
                            purpose: .transcription,
                            action: .install,
                            createdAt: "2026-07-24T10:00:00Z",
                            state: DownloadState(
                                modelID: "artifact",
                                phase: source
                            )
                        ),
                    ]
                )

                let isAllowed = ModelInstallQueue.allowsTransition(
                    from: source,
                    to: destination
                )
                if isAllowed {
                    XCTAssertNoThrow(
                        try queue.transition(
                            attemptID: "attempt",
                            to: DownloadState(
                                modelID: "artifact",
                                phase: destination
                            )
                        ),
                        "\(source) -> \(destination) should be allowed"
                    )
                } else {
                    XCTAssertThrowsError(
                        try queue.transition(
                            attemptID: "attempt",
                            to: DownloadState(
                                modelID: "artifact",
                                phase: destination
                            )
                        ),
                        "\(source) -> \(destination) should be forbidden"
                    )
                }
            }
        }
    }

    func testRetryCreatesNewTailAttemptAndAssociatesValidatedResumeData() throws {
        let reusable = ModelInstallResumableData(
            sourceAttemptID: "attempt-1",
            associatedAttemptID: "attempt-1",
            validatedBytes: 512,
            fileCount: 1
        )
        var queue = ModelInstallQueue(
            attempts: [
                ModelInstallQueueAttempt(
                    id: "attempt-1",
                    artifactID: "artifact-a",
                    purpose: .transcription,
                    action: .install,
                    createdAt: "2026-07-24T10:00:00Z",
                    state: DownloadState(
                        modelID: "artifact-a",
                        phase: .failed
                    ),
                    resumableData: reusable
                ),
                ModelInstallQueueAttempt(
                    id: "attempt-2",
                    artifactID: "artifact-b",
                    purpose: .transcription,
                    action: .install,
                    createdAt: "2026-07-24T10:01:00Z",
                    state: DownloadState(
                        modelID: "artifact-b",
                        phase: .queued
                    )
                ),
            ]
        )

        let retry = try queue.retry(
            attemptID: "attempt-1",
            newAttemptID: "attempt-3",
            createdAt: "2026-07-24T10:02:00Z"
        )

        XCTAssertEqual(queue.attempts.map(\.id), [
            "attempt-1",
            "attempt-2",
            "attempt-3",
        ])
        XCTAssertEqual(queue.attempt(id: "attempt-1")?.state.phase, .failed)
        XCTAssertEqual(retry.retryOfAttemptID, "attempt-1")
        XCTAssertEqual(retry.resumableData?.sourceAttemptID, "attempt-1")
        XCTAssertEqual(retry.resumableData?.associatedAttemptID, "attempt-3")
        XCTAssertEqual(retry.resumableData?.validatedBytes, 512)
    }

    func testRevokedAndCompletedAttemptsCannotRetryOrReturnToQueue() throws {
        for phase in [DownloadPhase.revoked, .installed] {
            var queue = ModelInstallQueue(
                attempts: [
                    ModelInstallQueueAttempt(
                        id: "attempt",
                        artifactID: "artifact",
                        purpose: .transcription,
                        action: .install,
                        createdAt: "2026-07-24T10:00:00Z",
                        state: DownloadState(
                            modelID: "artifact",
                            phase: phase
                        )
                    ),
                ]
            )

            XCTAssertThrowsError(
                try queue.retry(
                    attemptID: "attempt",
                    newAttemptID: "retry",
                    createdAt: "2026-07-24T10:01:00Z"
                )
            )
            XCTAssertThrowsError(
                try queue.transition(
                    attemptID: "attempt",
                    to: DownloadState(
                        modelID: "artifact",
                        phase: .queued
                    )
                )
            )
        }
    }

    func testRevokedAttemptRetainsVisibleNonresumableDataUntilExplicitRemoval() throws {
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
                phase: .revoked,
                bytesDownloaded: 512,
                totalBytes: 1_024
            )
        )
        try queue.associateResumableData(
            ModelInstallResumableData(
                sourceAttemptID: "attempt-1",
                associatedAttemptID: "attempt-1",
                validatedBytes: 512,
                fileCount: 1
            ),
            with: "attempt-1"
        )

        XCTAssertEqual(
            queue.attempt(id: "attempt-1")?.resumableData?.validatedBytes,
            512
        )
        XCTAssertThrowsError(
            try queue.retry(
                attemptID: "attempt-1",
                newAttemptID: "retry",
                createdAt: "2026-07-24T10:01:00Z"
            )
        )

        try queue.discardRetainedData(attemptID: "attempt-1")

        XCTAssertNil(queue.attempt(id: "attempt-1")?.resumableData)
        XCTAssertEqual(
            queue.attempt(id: "attempt-1")?.state.bytesDownloaded,
            512,
            "History remains truthful after retained bytes are removed."
        )
    }

    func testRetainedDataRemovalTargetsOnlyTheSelectedAttempt() throws {
        let firstData = ModelInstallResumableData(
            sourceAttemptID: "attempt-1",
            associatedAttemptID: "attempt-1",
            validatedBytes: 512,
            fileCount: 1,
            filenames: ["old-model.bin"]
        )
        let secondData = ModelInstallResumableData(
            sourceAttemptID: "attempt-2",
            associatedAttemptID: "attempt-2",
            validatedBytes: 1_024,
            fileCount: 1,
            filenames: ["new-model.bin"]
        )
        var queue = ModelInstallQueue(
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
                    resumableData: firstData
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
                    resumableData: secondData
                ),
            ]
        )

        try queue.discardRetainedData(attemptID: "attempt-1")

        XCTAssertNil(queue.attempt(id: "attempt-1")?.resumableData)
        XCTAssertEqual(
            queue.attempt(id: "attempt-2")?.resumableData,
            secondData
        )
    }

    func testCancelTargetsExactAttempt() throws {
        var queue = try twoAttemptQueue()

        try queue.cancel(attemptID: "attempt-2")

        XCTAssertEqual(queue.attempt(id: "attempt-1")?.state.phase, .queued)
        XCTAssertEqual(queue.attempt(id: "attempt-2")?.state.phase, .cancelled)
    }

    func testRelaunchRestoresFIFOAndRequeuesPreviouslyActiveAttempt() throws {
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
                        phase: .downloading,
                        bytesDownloaded: 400,
                        totalBytes: 1_000
                    )
                ),
                ModelInstallQueueAttempt(
                    id: "attempt-2",
                    artifactID: "artifact-b",
                    purpose: .voiceCleaning,
                    action: .install,
                    createdAt: "2026-07-24T10:01:00Z",
                    state: DownloadState(
                        modelID: "artifact-b",
                        phase: .queued
                    )
                ),
            ]
        )
        try store.save(queue)

        let restored = try store.loadForRelaunch()

        XCTAssertEqual(restored.attempts.map(\.id), ["attempt-1", "attempt-2"])
        XCTAssertEqual(restored.attempt(id: "attempt-1")?.state.phase, .queued)
        XCTAssertEqual(
            restored.attempt(id: "attempt-1")?.state.bytesDownloaded,
            400
        )
        XCTAssertEqual(restored.nextRunnableAttempt?.id, "attempt-1")
    }

    func testArtifactProjectionChangesOnlyAffectedRows() throws {
        var queue = try twoAttemptQueue()
        try queue.transition(
            attemptID: "attempt-1",
            to: DownloadState(
                modelID: "artifact-a",
                phase: .checkingSpace
            )
        )

        XCTAssertEqual(
            queue.latestStatesByArtifactID["artifact-a"]?.phase,
            .checkingSpace
        )
        XCTAssertEqual(
            queue.latestStatesByArtifactID["artifact-b"]?.phase,
            .queued
        )
        XCTAssertNil(queue.latestStatesByArtifactID["artifact-c"])
    }

    func testActiveAttemptWinsArtifactProjectionOverLaterRetry() throws {
        var queue = ModelInstallQueue(
            attempts: [
                ModelInstallQueueAttempt(
                    id: "failed-attempt",
                    artifactID: "artifact-a",
                    purpose: .transcription,
                    action: .install,
                    createdAt: "2026-07-24T10:00:00Z",
                    state: DownloadState(
                        modelID: "artifact-a",
                        phase: .failed
                    )
                ),
            ]
        )
        _ = try queue.retry(
            attemptID: "failed-attempt",
            newAttemptID: "active-retry",
            createdAt: "2026-07-24T10:01:00Z"
        )
        try queue.transition(
            attemptID: "active-retry",
            to: DownloadState(
                modelID: "artifact-a",
                phase: .checkingSpace
            )
        )
        try queue.transition(
            attemptID: "active-retry",
            to: DownloadState(
                modelID: "artifact-a",
                phase: .downloading,
                bytesDownloaded: 25,
                totalBytes: 100
            )
        )
        _ = try queue.retry(
            attemptID: "failed-attempt",
            newAttemptID: "later-retry",
            createdAt: "2026-07-24T10:02:00Z"
        )

        XCTAssertEqual(
            queue.latestStatesByArtifactID["artifact-a"]?.attemptID,
            "active-retry"
        )
        XCTAssertEqual(
            queue.latestStatesByArtifactID["artifact-a"]?.phase,
            .downloading
        )
    }

    func testResumeInspectorAssociatesOnlyValidatorBoundMatchingPartialData() throws {
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
        try Data(repeating: 1, count: 512).write(to: partialURL)
        try JSONEncoder().encode(
            DownloadResumeMetadata(
                modelID: "artifact-a",
                url: "https://github.com/Player0109/Textify/releases/download/models-v3/model.bin",
                expectedSize: 1_024,
                sha256: String(repeating: "a", count: 64),
                eTag: "\"fixture\"",
                lastModified: nil,
                bytesDownloaded: 512
            )
        ).write(to: metadataURL)
        let attempt = ModelInstallQueueAttempt(
            id: "attempt-1",
            artifactID: "artifact-a",
            purpose: .transcription,
            action: .install,
            createdAt: "2026-07-24T10:00:00Z",
            state: DownloadState(
                modelID: "artifact-a",
                phase: .failed
            )
        )

        let reusable = try ModelInstallResumableDataInspector(
            layout: layout
        ).inspect(
            for: attempt,
            expectedFiles: [
                ModelFile(
                    filename: "model.bin",
                    url: "https://github.com/Player0109/Textify/releases/download/models-v3/model.bin",
                    sha256: String(repeating: "a", count: 64),
                    sizeBytes: 1_024
                ),
            ]
        )

        XCTAssertEqual(
            reusable,
            ModelInstallResumableData(
                sourceAttemptID: "attempt-1",
                associatedAttemptID: "attempt-1",
                validatedBytes: 512,
                fileCount: 1,
                filenames: ["model.bin"]
            )
        )

        try Data(repeating: 1, count: 511).write(to: partialURL)
        XCTAssertNil(
            try ModelInstallResumableDataInspector(
                layout: layout
            ).inspect(
                for: attempt,
                expectedFiles: [
                    ModelFile(
                        filename: "model.bin",
                        url: "https://github.com/Player0109/Textify/releases/download/models-v3/model.bin",
                        sha256: String(repeating: "a", count: 64),
                        sizeBytes: 1_024
                    ),
                ]
            )
        )

        try Data(repeating: 1, count: 512).write(to: partialURL)
        XCTAssertNil(
            try ModelInstallResumableDataInspector(
                layout: layout
            ).inspect(
                for: attempt,
                expectedFiles: [
                    ModelFile(
                        filename: "model.bin",
                        url: "https://github.com/Player0109/Textify/releases/download/models-v3/model.bin",
                        sha256: String(repeating: "b", count: 64),
                        sizeBytes: 1_024
                    ),
                ]
            )
        )
    }

    func testRevokedAttemptReportsValidatedDirectoryStagingAsRetainedData() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let layout = ModelStorageLayout(rootDirectory: directory)
        let stagingDirectory = layout.downloadsDirectory
            .appendingPathComponent(
                ".artifact-a.installing-fixture",
                isDirectory: true
            )
        let stagedFile = stagingDirectory
            .appendingPathComponent("encoder/model.bin")
        try FileManager.default.createDirectory(
            at: stagedFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 7, count: 512).write(to: stagedFile)
        let attempt = ModelInstallQueueAttempt(
            id: "attempt-1",
            artifactID: "artifact-a",
            purpose: .transcription,
            action: .install,
            createdAt: "2026-07-24T10:00:00Z",
            state: DownloadState(
                modelID: "artifact-a",
                phase: .revoked
            )
        )

        let retained = try ModelInstallResumableDataInspector(
            layout: layout
        ).inspect(
            for: attempt,
            expectedFiles: [
                ModelFile(
                    filename: "model.bin",
                    relativePath: "encoder/model.bin",
                    url: "https://github.com/Player0109/Textify/releases/download/models-v3/model.bin",
                    sha256: String(repeating: "a", count: 64),
                    sizeBytes: 512
                ),
            ]
        )

        XCTAssertEqual(retained?.validatedBytes, 512)
        XCTAssertEqual(retained?.fileCount, 1)
        XCTAssertEqual(retained?.filenames, ["model.bin"])
    }

    func testResumeInspectorDoesNotCreditSparsePreallocation() throws {
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
        FileManager.default.createFile(
            atPath: partialURL.path,
            contents: nil
        )
        let handle = try FileHandle(forWritingTo: partialURL)
        try handle.truncate(atOffset: 1_048_576)
        try handle.close()
        try JSONEncoder().encode(
            DownloadResumeMetadata(
                modelID: "artifact-a",
                url: "https://github.com/Player0109/Textify/releases/download/models-v3/model.bin",
                expectedSize: 2_097_152,
                sha256: String(repeating: "a", count: 64),
                eTag: "\"fixture\"",
                lastModified: nil,
                bytesDownloaded: 1_048_576
            )
        ).write(to: metadataURL)
        let attempt = ModelInstallQueueAttempt(
            id: "attempt-1",
            artifactID: "artifact-a",
            purpose: .transcription,
            action: .install,
            createdAt: "2026-07-24T10:00:00Z",
            state: DownloadState(
                modelID: "artifact-a",
                phase: .failed
            )
        )

        XCTAssertNil(
            try ModelInstallResumableDataInspector(
                layout: layout
            ).inspect(
                for: attempt,
                expectedFiles: [
                    ModelFile(
                        filename: "model.bin",
                        url: "https://github.com/Player0109/Textify/releases/download/models-v3/model.bin",
                        sha256: String(repeating: "a", count: 64),
                        sizeBytes: 2_097_152
                    ),
                ]
            )
        )
    }

    func testExplicitRetainedDataRemovalDeletesPartialMetadataAndStagingBytes() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = ModelStorageLayout(rootDirectory: root)
        let installedDirectory = try layout.installedModelDirectory(
            modelID: "artifact-a"
        )
        try FileManager.default.createDirectory(
            at: layout.downloadsDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: installedDirectory,
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
        let directoryStagingURL = layout.downloadsDirectory
            .appendingPathComponent(".artifact-a.installing-fixture")
        let fileStagingURL = installedDirectory
            .appendingPathComponent(".model.bin.installing-fixture")
        try Data("partial".utf8).write(to: partialURL)
        try Data("metadata".utf8).write(to: metadataURL)
        try FileManager.default.createDirectory(
            at: directoryStagingURL,
            withIntermediateDirectories: true
        )
        try Data("staged".utf8).write(to: fileStagingURL)

        try ModelInstallRetainedDataRemover(layout: layout).remove(
            modelID: "artifact-a",
            expectedFiles: [
                ModelFile(
                    filename: "model.bin",
                    url: "https://github.com/Player0109/Textify/releases/download/models-v3/model.bin",
                    sha256: String(repeating: "a", count: 64),
                    sizeBytes: 7
                ),
            ]
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: partialURL.path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: metadataURL.path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directoryStagingURL.path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fileStagingURL.path)
        )
    }

    func testFreshAttemptIsolationSurvivesStagingCleanupUntilExplicitRemoval() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = ModelStorageLayout(rootDirectory: root)
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

        try ModelInstallRetainedDataIsolator(layout: layout).isolate(
            modelID: "artifact-a",
            filenames: ["model.bin"]
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: partialURL.path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: metadataURL.path)
        )
        let archives = try FileManager.default.contentsOfDirectory(
            at: layout.downloadsDirectory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix(
                ".artifact-a.retained-"
            )
        }
        let partialArchive = try XCTUnwrap(
            archives.first {
                FileManager.default.fileExists(
                    atPath: $0.appendingPathComponent(
                        partialURL.lastPathComponent
                    ).path
                )
            }
        )
        let stagingArchive = try XCTUnwrap(
            archives.first {
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
                atPath: partialArchive.appendingPathComponent(
                    metadataURL.lastPathComponent
                ).path
            )
        )

        let liveStaging = layout.downloadsDirectory.appendingPathComponent(
            ".artifact-a.installing-fresh",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: liveStaging,
            withIntermediateDirectories: true
        )
        let remover = ModelInstallRetainedDataRemover(layout: layout)
        try remover.removeDirectoryStaging(modelID: "artifact-a")

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: liveStaging.path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: partialArchive.path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: stagingArchive.path)
        )

        try remover.remove(
            modelID: "artifact-a",
            filenames: ["model.bin"]
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: partialArchive.path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: stagingArchive.path)
        )
    }

    private func twoAttemptQueue() throws -> ModelInstallQueue {
        var queue = ModelInstallQueue()
        _ = try queue.authorize(
            artifactID: "artifact-a",
            purpose: .transcription,
            action: .install,
            attemptID: "attempt-1",
            createdAt: "2026-07-24T10:00:00Z"
        )
        _ = try queue.authorize(
            artifactID: "artifact-b",
            purpose: .voiceCleaning,
            action: .install,
            attemptID: "attempt-2",
            createdAt: "2026-07-24T10:01:00Z"
        )
        return queue
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TextifyModelInstallQueueTests-\(UUID().uuidString)",
                isDirectory: true
            )
    }
}
