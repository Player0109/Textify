import Foundation
import TextifyModels
import XCTest

final class ModelInstallQueueTests: XCTestCase {
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
        ).inspect(for: attempt)

        XCTAssertEqual(
            reusable,
            ModelInstallResumableData(
                sourceAttemptID: "attempt-1",
                associatedAttemptID: "attempt-1",
                validatedBytes: 512,
                fileCount: 1
            )
        )

        try Data(repeating: 1, count: 511).write(to: partialURL)
        XCTAssertNil(
            try ModelInstallResumableDataInspector(
                layout: layout
            ).inspect(for: attempt)
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
