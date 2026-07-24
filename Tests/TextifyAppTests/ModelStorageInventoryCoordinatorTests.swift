@testable import Textify
import TextifyModels
import XCTest

final class ModelStorageInventoryCoordinatorTests: XCTestCase {
    @MainActor
    func testRefreshesCoalesceAndOnlyNewestGenerationPublishes() async {
        let probe = StorageInventoryLoadProbe()
        let coordinator = ModelStorageInventoryCoordinator { _ in
            try await probe.load()
        }

        coordinator.refresh(installedRecords: [])
        await probe.waitUntilRequestCount(1)
        coordinator.refresh(installedRecords: [])
        coordinator.refresh(installedRecords: [])
        await probe.completeOldest(with: snapshot(totalBytes: 10))

        XCTAssertEqual(coordinator.state, .calculating)
        await probe.waitUntilRequestCount(2)
        let requestCount = await probe.requestCount
        XCTAssertEqual(requestCount, 2)

        await probe.completeOldest(with: snapshot(totalBytes: 30))
        await waitUntil {
            coordinator.state == .available(
                generation: 3,
                snapshot: self.snapshot(totalBytes: 30)
            )
        }
    }

    @MainActor
    func testFailurePublishesSizeUnavailableForNewestGeneration() async {
        let coordinator = ModelStorageInventoryCoordinator { _ in
            throw ModelStorageInventoryError.filesystemReadFailed("fixture")
        }

        coordinator.refresh(installedRecords: [])

        await waitUntil {
            coordinator.state == .unavailable(generation: 1)
        }
    }

    private func snapshot(totalBytes: Int64) -> ModelStorageInventorySnapshot {
        ModelStorageInventorySnapshot(
            artifacts: [],
            summary: ModelStorageInventorySummary(
                installedArtifactCount: 0,
                installedModelStorageBytes: 0,
                downloadStorageBytes: 0,
                otherModelDataBytes: totalBytes,
                totalManagedStorageBytes: totalBytes,
                availableSpaceBytes: 100
            )
        )
    }

    @MainActor
    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0 ..< 2000 {
            if predicate() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for inventory state.")
    }
}

private actor StorageInventoryLoadProbe {
    private(set) var requestCount = 0
    private var continuations: [
        CheckedContinuation<ModelStorageInventorySnapshot, Error>
    ] = []
    private var requestWaiters: [
        Int: [CheckedContinuation<Void, Never>]
    ] = [:]

    func load() async throws -> ModelStorageInventorySnapshot {
        requestCount += 1
        requestWaiters.removeValue(forKey: requestCount)?
            .forEach { $0.resume() }
        return try await withCheckedThrowingContinuation {
            continuations.append($0)
        }
    }

    func waitUntilRequestCount(_ expected: Int) async {
        guard requestCount < expected else {
            return
        }
        await withCheckedContinuation {
            requestWaiters[expected, default: []].append($0)
        }
    }

    func completeOldest(
        with snapshot: ModelStorageInventorySnapshot
    ) {
        continuations.removeFirst().resume(returning: snapshot)
    }
}
