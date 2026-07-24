import Foundation
@testable import Textify
import TextifyModels
import XCTest

final class ModelInstallCoordinatorQueueTests: XCTestCase {
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
    func testWaitingHeadPersistsAndBlocksLaterFIFOAttemptUntilResumed() async throws {
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
        coordinator.resume(attemptID: "attempt-1")
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

private actor InstallReadinessProbe {
    private var waitingArtifacts: Set<String> = ["artifact-a"]

    func shouldWaitForNetwork(_ artifactID: String) -> Bool {
        waitingArtifacts.contains(artifactID)
    }

    func setNetworkAvailable(for artifactID: String) {
        waitingArtifacts.remove(artifactID)
    }
}
