@testable import Textify
import Darwin.Mach
import Foundation
import TextifyModels
import XCTest

final class ModelCatalogDerivationTests: XCTestCase {
    func testProgressTickOnlyAdvancesLocalOverlayVersion() async throws {
        let manifest = try productionManifest()
        let modelID = try XCTUnwrap(manifest.models.first?.id)
        let engine = ModelCatalogDerivationEngine()
        let initial = request(
            manifest: manifest,
            localRevision: 1,
            transferState: transfer(
                modelID: modelID,
                bytesDownloaded: 10
            )
        )

        let first = try await engine.derive(initial)
        let second = try await engine.derive(
            request(
                manifest: manifest,
                localRevision: 2,
                transferState: transfer(
                    modelID: modelID,
                    bytesDownloaded: 20
                )
            )
        )

        XCTAssertEqual(second.versions.catalogIndex, first.versions.catalogIndex)
        XCTAssertEqual(second.versions.eligibilityIndex, first.versions.eligibilityIndex)
        XCTAssertEqual(second.versions.queryResult, first.versions.queryResult)
        XCTAssertGreaterThan(
            second.versions.localStateOverlay,
            first.versions.localStateOverlay
        )
        XCTAssertEqual(
            second.experience.rows.first { $0.id == modelID }?
                .installState?.bytesDownloaded,
            20
        )
    }

    func testQueryAndCatalogHaveIndependentInvalidationBoundaries() async throws {
        let manifest = try productionManifest()
        let engine = ModelCatalogDerivationEngine()
        let initialRequest = request(manifest: manifest, localRevision: 1)
        let initial = try await engine.derive(initialRequest)

        var searchedRequest = initialRequest
        searchedRequest.query.searchText = "whisper"
        let searched = try await engine.derive(searchedRequest)

        XCTAssertEqual(searched.versions.catalogIndex, initial.versions.catalogIndex)
        XCTAssertEqual(
            searched.versions.eligibilityIndex,
            initial.versions.eligibilityIndex
        )
        XCTAssertEqual(
            searched.versions.localStateOverlay,
            initial.versions.localStateOverlay
        )
        XCTAssertGreaterThan(
            searched.versions.queryResult,
            initial.versions.queryResult
        )

        var replacedManifest = manifest
        replacedManifest = ModelManifest(
            manifestVersion: replacedManifest.manifestVersion,
            generatedAt: "2026-07-25T00:00:00Z",
            models: replacedManifest.models,
            presentationGraph: replacedManifest.presentationGraph,
            artifactAliases: replacedManifest.artifactAliases
        )
        let replaced = try await engine.derive(
            request(manifest: replacedManifest, localRevision: 1)
        )

        XCTAssertGreaterThan(
            replaced.versions.catalogIndex,
            searched.versions.catalogIndex
        )
        XCTAssertGreaterThan(
            replaced.versions.eligibilityIndex,
            searched.versions.eligibilityIndex
        )
        XCTAssertGreaterThan(
            replaced.versions.queryResult,
            searched.versions.queryResult
        )
    }

    @MainActor
    func testCoordinatorPublishesOnlyNewestGeneration() async throws {
        let manifest = try productionManifest()
        let engine = ModelCatalogDerivationEngine { request in
            if request.query.searchText == "old" {
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        let coordinator = ModelCatalogDerivationCoordinator(
            engine: engine,
            searchDebounceNanoseconds: 0
        )
        var oldRequest = request(manifest: manifest, localRevision: 1)
        oldRequest.query.searchText = "old"
        var newestRequest = oldRequest
        newestRequest.query.searchText = "whisper"

        coordinator.submit(oldRequest)
        coordinator.submit(newestRequest)
        await coordinator.waitUntilSettled()

        XCTAssertEqual(coordinator.snapshot?.query.searchText, "whisper")
        XCTAssertEqual(coordinator.publishedGeneration, 2)
    }

    @MainActor
    func testSearchDebouncesWithinSpecifiedWindow() async throws {
        let manifest = ModelManifest(
            manifestVersion: 1,
            generatedAt: "2026-07-25T00:00:00Z",
            models: []
        )
        let coordinator = ModelCatalogDerivationCoordinator()
        let initial = request(manifest: manifest, localRevision: 1)
        coordinator.submit(initial)
        await coordinator.waitUntilSettled()

        var searched = initial
        searched.query.searchText = "whisper"
        let startedAt = CFAbsoluteTimeGetCurrent()
        coordinator.submit(searched)
        await coordinator.waitUntilSettled()
        let elapsed = CFAbsoluteTimeGetCurrent() - startedAt

        XCTAssertGreaterThanOrEqual(elapsed, 0.100)
        XCTAssertLessThan(elapsed, 0.250)
    }

    func testReleaseStressCatalogBudgets() async throws {
        guard ProcessInfo.processInfo.environment[
            "TEXTIFY_RUN_CATALOG_STRESS"
        ] == "1" else {
            throw XCTSkip(
                "Set TEXTIFY_RUN_CATALOG_STRESS=1 and run this test in Release."
            )
        }

        let productionScale = try stressManifest(
            checkpointCount: 500,
            artifactsPerCheckpoint: 4
        )
        let productionEngine = ModelCatalogDerivationEngine()
        var productionRequest = request(
            manifest: productionScale,
            localRevision: 1
        )
        let cold = try await productionEngine.derive(productionRequest)
        XCTAssertEqual(
            cold.indexStatistics,
            ModelCatalogIndexStatistics(
                families: 1,
                checkpoints: 500,
                exactArtifacts: 2_000
            )
        )

        var queryDurations: [TimeInterval] = []
        for index in 0 ..< 20 {
            productionRequest.query.searchText =
                "artifact-\(index)-"
            let startedAt = CFAbsoluteTimeGetCurrent()
            let result = try await productionEngine.derive(
                productionRequest
            )
            queryDurations.append(
                CFAbsoluteTimeGetCurrent() - startedAt
            )
            XCTAssertFalse(result.experience.rows.isEmpty)
        }
        let queryP95 = percentile95(queryDurations)
        XCTAssertLessThan(
            queryP95,
            0.250,
            "Search/filter/sort derivation must settle within 250 ms at p95."
        )
        XCTAssertLessThan(
            queryDurations[1],
            0.100,
            "A submitted warm search must return useful results within 100 ms."
        )
        var filterDurations: [TimeInterval] = []
        productionRequest.query.searchText = ""
        for index in 0 ..< 20 {
            productionRequest.query.scope =
                index.isMultiple(of: 4) ? .installed : .all
            productionRequest.query.sort =
                index.isMultiple(of: 2) ? .downloadSize : .catalog
            productionRequest.query.numericFormats =
                index.isMultiple(of: 3) ? [.q5_1] : []
            let startedAt = CFAbsoluteTimeGetCurrent()
            _ = try await productionEngine.derive(productionRequest)
            filterDurations.append(
                CFAbsoluteTimeGetCurrent() - startedAt
            )
        }
        let filterP95 = percentile95(filterDurations)
        XCTAssertLessThan(
            filterP95,
            0.250,
            "Filter and sort derivation must settle within 250 ms at p95."
        )

        let stressScale = try stressManifest(
            checkpointCount: 2_000,
            artifactsPerCheckpoint: 5
        )
        let stressEngine = ModelCatalogDerivationEngine()
        var stressRequest = request(
            manifest: stressScale,
            localRevision: 1,
            transferState: transfer(
                modelID: "artifact-0-0",
                bytesDownloaded: 1
            )
        )
        let stressSnapshot = try await stressEngine.derive(stressRequest)
        XCTAssertEqual(
            stressSnapshot.indexStatistics,
            ModelCatalogIndexStatistics(
                families: 1,
                checkpoints: 2_000,
                exactArtifacts: 10_000
            )
        )
        XCTAssertEqual(stressSnapshot.experience.rows.count, 10_000)

        var mutationDurations: [TimeInterval] = []
        var previous = stressSnapshot
        for tick in 2 ... 21 {
            stressRequest = request(
                manifest: stressScale,
                localRevision: UInt64(tick),
                transferState: transfer(
                    modelID: "artifact-0-0",
                    bytesDownloaded: Int64(tick)
                )
            )
            let startedAt = CFAbsoluteTimeGetCurrent()
            let updated = try await stressEngine.derive(stressRequest)
            mutationDurations.append(
                CFAbsoluteTimeGetCurrent() - startedAt
            )
            XCTAssertEqual(
                updated.versions.queryResult,
                previous.versions.queryResult
            )
            XCTAssertEqual(updated.experience.rows.count, 10_000)
            previous = updated
        }
        let mutationP95 = percentile95(mutationDurations)
        XCTAssertLessThan(
            mutationP95,
            0.100,
            "Visible progress mutations must settle within 100 ms at p95."
        )

        stressRequest.query.searchText = "artifact-1999-4"
        let exactSearch = try await stressEngine.derive(stressRequest)
        XCTAssertEqual(
            exactSearch.experience.rows.map(\.id),
            ["artifact-1999-4"]
        )

        stressRequest.query.searchText = ""
        stressRequest.query.scope = .installed
        let installedScope = try await stressEngine.derive(stressRequest)
        XCTAssertTrue(installedScope.experience.rows.isEmpty)

        stressRequest.query.scope = .all
        for index in 0 ..< 10 {
            stressRequest.query.searchText =
                "artifact-\(1_900 + index)-"
            let warmResult = try await stressEngine.derive(stressRequest)
            XCTAssertEqual(warmResult.experience.rows.count, 5)
        }
        let residentBytesAfterWarmup = residentMemoryBytes()
        for index in 0 ..< 30 {
            stressRequest.query.searchText =
                "artifact-\(1_900 + index % 10)-"
            let repeatedResult = try await stressEngine.derive(stressRequest)
            XCTAssertEqual(repeatedResult.experience.rows.count, 5)
        }
        let finalResidentBytes = residentMemoryBytes()
        let residentGrowth = finalResidentBytes > residentBytesAfterWarmup
            ? finalResidentBytes - residentBytesAfterWarmup
            : 0
        XCTAssertLessThan(
            residentGrowth,
            256 * 1_024 * 1_024,
            "Repeated 10,000-artifact queries must have bounded resident growth."
        )
        print(
            String(
                format:
                    "Model catalog release stress: query p95 %.1f ms; "
                    + "filter/scope/sort p95 %.1f ms; progress p95 %.1f ms; "
                    + "10,000-artifact rows %d; resident growth %.1f MiB",
                queryP95 * 1_000,
                filterP95 * 1_000,
                mutationP95 * 1_000,
                previous.experience.rows.count,
                Double(residentGrowth) / Double(1_024 * 1_024)
            )
        )
    }

    private func request(
        manifest: ModelManifest,
        localRevision: UInt64,
        transferState: DownloadState? = nil
    ) -> ModelCatalogDerivationRequest {
        ModelCatalogDerivationRequest(
            catalogRevision: manifest.generatedAt,
            trustedManifest: manifest,
            compatibilityContext: ModelCatalogCompatibilityContext(
                appVersion: "1.1.0",
                macOSVersion: "14.0",
                architecture: .arm64,
                physicalMemoryBytes: 16_000_000_000
            ),
            localRevision: localRevision,
            installedRecords: [],
            activeTranscriptionModelID: nil,
            activeVoiceCleaningModelID: nil,
            transferStatesByModelID: transferState.map {
                [$0.modelID: $0]
            } ?? [:],
            revocationOverlay: .init(),
            managedReadinessByModelID: [:],
            onDiskBytesByModelID: [:],
            storageInventoryByModelID: [:],
            installedSizeStatus: .measured,
            query: ModelCatalogQuery(purpose: .transcription)
        )
    }

    private func transfer(
        modelID: String,
        bytesDownloaded: Int64
    ) -> DownloadState {
        DownloadState(
            modelID: modelID,
            phase: .downloading,
            bytesDownloaded: bytesDownloaded,
            totalBytes: 100,
            message: "Downloading"
        )
    }

    private func productionManifest() throws -> ModelManifest {
        try ModelManifest.decode(
            Data(
                contentsOf: repositoryRoot
                    .appendingPathComponent("models/manifest.json")
            )
        )
    }

    private func stressManifest(
        checkpointCount: Int,
        artifactsPerCheckpoint: Int
    ) throws -> ModelManifest {
        let sourceData = try Data(
            contentsOf: repositoryRoot
                .appendingPathComponent("models/manifest.json")
        )
        let source = try XCTUnwrap(
            JSONSerialization.jsonObject(with: sourceData)
                as? [String: Any]
        )
        let sourceModels = try XCTUnwrap(
            source["models"] as? [[String: Any]]
        )
        let sourceGraph = try XCTUnwrap(
            source["presentationGraph"] as? [String: Any]
        )
        let sourceFamilies = try XCTUnwrap(
            sourceGraph["families"] as? [[String: Any]]
        )
        let sourceCheckpoints = try XCTUnwrap(
            sourceGraph["checkpoints"] as? [[String: Any]]
        )
        let sourceArtifacts = try XCTUnwrap(
            sourceGraph["artifacts"] as? [[String: Any]]
        )
        let modelTemplate = try XCTUnwrap(sourceModels.first)
        let familyTemplate = try XCTUnwrap(sourceFamilies.first)
        let checkpointTemplate = try XCTUnwrap(sourceCheckpoints.first)
        let artifactTemplate = try XCTUnwrap(sourceArtifacts.first)

        var models: [[String: Any]] = []
        var checkpoints: [[String: Any]] = []
        var artifacts: [[String: Any]] = []
        var checkpointIDs: [String] = []
        models.reserveCapacity(checkpointCount * artifactsPerCheckpoint)
        checkpoints.reserveCapacity(checkpointCount)
        artifacts.reserveCapacity(checkpointCount * artifactsPerCheckpoint)
        checkpointIDs.reserveCapacity(checkpointCount)

        for checkpointIndex in 0 ..< checkpointCount {
            let checkpointID = "checkpoint-\(checkpointIndex)"
            checkpointIDs.append(checkpointID)
            var artifactIDs: [String] = []
            artifactIDs.reserveCapacity(artifactsPerCheckpoint)

            for artifactIndex in 0 ..< artifactsPerCheckpoint {
                let artifactID =
                    "artifact-\(checkpointIndex)-\(artifactIndex)"
                artifactIDs.append(artifactID)

                var model = modelTemplate
                model["id"] = artifactID
                model["displayName"] = artifactID
                model["description"] = "\(artifactID) stress fixture"
                model["benchmark"] = nil
                if var runtime = model["runtime"] as? [String: Any] {
                    runtime["variant"] = artifactID
                    model["runtime"] = runtime
                }
                models.append(model)

                var artifact = artifactTemplate
                artifact["id"] = artifactID
                if var presentation =
                    artifact["presentation"] as? [String: Any] {
                    presentation["displayName"] =
                        "Variant \(artifactIndex)"
                    presentation["curatedRank"] = artifactIndex
                    artifact["presentation"] = presentation
                }
                artifacts.append(artifact)
            }

            var checkpoint = checkpointTemplate
            checkpoint["id"] = checkpointID
            checkpoint["artifactIDs"] = artifactIDs
            checkpoint["recommendedArtifactID"] = artifactIDs[0]
            checkpoint["fallbackArtifactIDs"] =
                Array(artifactIDs.dropFirst())
            if var presentation =
                checkpoint["presentation"] as? [String: Any] {
                presentation["displayName"] =
                    "Checkpoint \(checkpointIndex)"
                presentation["curatedRank"] = checkpointIndex
                checkpoint["presentation"] = presentation
            }
            checkpoints.append(checkpoint)
        }

        var family = familyTemplate
        family["id"] = "stress-family"
        family["checkpointIDs"] = checkpointIDs
        if var presentation = family["presentation"] as? [String: Any] {
            presentation["displayName"] = "Stress Family"
            presentation["curatedRank"] = 0
            family["presentation"] = presentation
        }
        let root: [String: Any] = [
            "manifestVersion": 3,
            "generatedAt": "2026-07-25T00:00:00Z",
            "models": models,
            "presentationGraph": [
                "families": [family],
                "checkpoints": checkpoints,
                "artifacts": artifacts,
            ],
            "artifactAliases": [],
        ]
        return try ModelManifest.decode(
            JSONSerialization.data(withJSONObject: root)
        )
    }

    private func percentile95(
        _ durations: [TimeInterval]
    ) -> TimeInterval {
        let sorted = durations.sorted()
        return sorted[max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
    }

    private func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size
                / MemoryLayout<natural_t>.size
        )
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        XCTAssertEqual(status, KERN_SUCCESS)
        return UInt64(info.resident_size)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
