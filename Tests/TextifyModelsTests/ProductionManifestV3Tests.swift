import Foundation
import TextifyModels
import XCTest

final class ProductionManifestV3Tests: XCTestCase {
    func testSignedProductionCatalogIsCompleteV3PresentationGraph() throws {
        let manifest = try verifiedProductionManifest()
        let graph = try XCTUnwrap(manifest.presentationGraph)

        XCTAssertEqual(manifest.manifestVersion, 3)
        XCTAssertNoThrow(try ProductionModelPolicy.validateProductionManifest(manifest))
        XCTAssertEqual(graph.artifacts.count, manifest.models.count)
        XCTAssertEqual(Set(graph.artifacts.map(\.id)), Set(manifest.models.map(\.id)))
        XCTAssertTrue(
            Dictionary(grouping: graph.artifacts, by: \.id)
                .values
                .allSatisfy { $0.count == 1 }
        )
        XCTAssertTrue(graph.artifacts.allSatisfy { !$0.presentation.displayName.isEmpty })
        XCTAssertTrue(
            graph.checkpoints.allSatisfy {
                $0.artifactIDs.contains($0.recommendedArtifactID)
            }
        )

        let qwenMLX = try artifact("qwen3-asr-0.6b-mlx-8bit", in: graph)
        XCTAssertEqual(qwenMLX.artifactFormat, .mlx)
        XCTAssertEqual(qwenMLX.numericFormat, .eightBit)
        let qwenGGUF = try artifact("qwen3-asr-0.6b-bf16", in: graph)
        XCTAssertEqual(qwenGGUF.artifactFormat, .gguf)
        XCTAssertEqual(qwenGGUF.numericFormat, .bf16)
        let parakeetCoreML = try artifact("parakeet-tdt-0.6b-v3", in: graph)
        XCTAssertEqual(parakeetCoreML.artifactFormat, .coreML)
        XCTAssertEqual(parakeetCoreML.numericFormat, .int8)
        XCTAssertEqual(parakeetCoreML.computeRoute, .coreMLNeuralEngine)
        let parakeet110M = try artifact("parakeet-tdt-ctc-110m", in: graph)
        XCTAssertEqual(parakeet110M.artifactFormat, .coreML)
        XCTAssertEqual(parakeet110M.numericFormat, .fp32)
        let reazonONNX = try artifact("reazonspeech-k2-v2-int8", in: graph)
        XCTAssertEqual(reazonONNX.artifactFormat, .onnx)
        XCTAssertEqual(reazonONNX.numericFormat, .int8)
        XCTAssertEqual(reazonONNX.computeRoute, .cpuOnly)
        let whisperGGML = try artifact("ggml-small.en-q5_1", in: graph)
        XCTAssertEqual(whisperGGML.artifactFormat, .ggml)
        XCTAssertEqual(whisperGGML.numericFormat, .q5_1)
        XCTAssertEqual(whisperGGML.computeRoute, .gpuViaMetal)
    }

    func testProductionV3PreservesV2OperationalRecordsExceptSignedPeakStorageBounds() throws {
        let v2Data = try fixtureData("manifest_v2.production-migration.json")
        let v3Data = try Data(
            contentsOf: repositoryRoot.appendingPathComponent("models/manifest.json")
        )
        let v2Models = try rawModels(in: v2Data)
        var v3Models = try rawModels(in: v3Data)
        for index in v3Models.indices {
            v3Models[index].removeValue(forKey: "installationStorage")
        }
        XCTAssertEqual(
            try JSONSerialization.data(
                withJSONObject: v3Models,
                options: [.sortedKeys]
            ),
            try JSONSerialization.data(
                withJSONObject: v2Models,
                options: [.sortedKeys]
            )
        )

        let v2 = try ModelManifest.decode(v2Data)
        let v3 = try verifiedProductionManifest()

        XCTAssertEqual(v2.manifestVersion, 2)
        XCTAssertEqual(v2.models.count, 43)
        XCTAssertEqual(
            v3.models.map(removingInstallationStorage),
            v2.models
        )
        XCTAssertTrue(
            v3.models.allSatisfy {
                $0.installationStorage
                    == ModelInstallationStorage(
                        finalArtifactBytes: $0.sizeBytes,
                        peakInstallationBytes: $0.sizeBytes
                    )
            }
        )
    }

    func testV2MigrationFixtureResolvesAllLocalConditionsWithoutChangingActiveIdentity() throws {
        let fixture = try JSONDecoder().decode(
            MigrationFixture.self,
            from: fixtureData("production_v2_migration_states.json")
        )
        let v2 = try ModelManifest.decode(fixtureData("manifest_v2.production-migration.json"))
        let v3 = try verifiedProductionManifest()
        let graph = try XCTUnwrap(v3.presentationGraph)

        XCTAssertEqual(fixture.sourceManifestVersion, 2)
        XCTAssertEqual(
            Set(fixture.records.map(\.condition)),
            [.installed, .active, .missing, .corrupt, .partial]
        )
        XCTAssertEqual(
            fixture.records.first(where: { $0.condition == .active })?.artifactID,
            fixture.activeArtifactID
        )

        for record in fixture.records {
            let previousArtifact = try XCTUnwrap(
                v2.models.first { $0.id == record.artifactID },
                "Missing v2 fixture artifact \(record.artifactID)"
            )
            let currentArtifact = try XCTUnwrap(
                v3.models.first { $0.id == record.artifactID },
                "Missing v3 artifact \(record.artifactID)"
            )
            let expectedFile = try XCTUnwrap(
                previousArtifact.files.first { $0.filename == record.filename }
            )
            XCTAssertEqual(
                removingInstallationStorage(currentArtifact),
                previousArtifact
            )
            XCTAssertEqual(
                graph.artifacts.filter { $0.id == record.artifactID }.count,
                1
            )

            switch record.condition {
            case .installed, .active:
                XCTAssertTrue(record.receiptPresent)
                XCTAssertTrue(record.filePresent)
                XCTAssertEqual(record.observedSizeBytes, expectedFile.sizeBytes)
                XCTAssertEqual(record.observedSHA256, expectedFile.sha256)
            case .missing:
                XCTAssertTrue(record.receiptPresent)
                XCTAssertFalse(record.filePresent)
                XCTAssertNil(record.observedSizeBytes)
                XCTAssertNil(record.observedSHA256)
            case .corrupt:
                XCTAssertTrue(record.receiptPresent)
                XCTAssertTrue(record.filePresent)
                XCTAssertEqual(record.observedSizeBytes, expectedFile.sizeBytes)
                XCTAssertNotEqual(record.observedSHA256, expectedFile.sha256)
            case .partial:
                XCTAssertFalse(record.receiptPresent)
                XCTAssertTrue(record.filePresent)
                XCTAssertLessThan(record.observedSizeBytes ?? .max, expectedFile.sizeBytes)
                XCTAssertNil(record.observedSHA256)
            }
        }

        XCTAssertEqual(fixture.activeArtifactID, "qwen3-asr-1.7b-bf16")
    }

    private func verifiedProductionManifest() throws -> ModelManifest {
        let verifier = ManifestVerifier(trustedKeys: [
            TrustedModelManifestKey(
                keyId: "textify-model-manifest-2026-huggingface",
                publicKeyBase64: "eg6XVGVQ4Kqh1dtN3B8JcFTtK0RSxkxd79W5tfIlfos="
            ),
        ])
        return try verifier.verify(
            manifestData: Data(
                contentsOf: repositoryRoot.appendingPathComponent("models/manifest.json")
            ),
            signatureData: Data(
                contentsOf: repositoryRoot.appendingPathComponent("models/manifest.json.sig")
            )
        )
    }

    private func artifact(
        _ id: String,
        in graph: ModelCatalogPresentationGraph
    ) throws -> ModelExactArtifactPresentationNode {
        try XCTUnwrap(graph.artifacts.first { $0.id == id })
    }

    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: nil,
                subdirectory: "Fixtures/Models"
            )
        )
        return try Data(contentsOf: url)
    }

    private func rawModels(in data: Data) throws -> [[String: Any]] {
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return try XCTUnwrap(json["models"] as? [[String: Any]])
    }

    private func removingInstallationStorage(
        _ model: ModelEntry
    ) -> ModelEntry {
        ModelEntry(
            id: model.id,
            displayName: model.displayName,
            tier: model.tier,
            description: model.description,
            sizeBytes: model.sizeBytes,
            files: model.files,
            licenses: model.licenses,
            provenance: model.provenance,
            runtimeParameters: model.runtimeParameters,
            hallucinationThresholds: model.hallucinationThresholds,
            minAppVersion: model.minAppVersion,
            runtime: model.runtime,
            capabilities: model.capabilities,
            presentation: model.presentation,
            purpose: model.purpose,
            installationStorage: nil,
            benchmark: model.benchmark
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct MigrationFixture: Decodable {
    let sourceManifestVersion: Int
    let activeArtifactID: String
    let records: [MigrationRecord]
}

private struct MigrationRecord: Decodable {
    let artifactID: String
    let condition: MigrationCondition
    let filename: String
    let receiptPresent: Bool
    let filePresent: Bool
    let observedSizeBytes: Int64?
    let observedSHA256: String?
}

private enum MigrationCondition: String, Decodable, Hashable {
    case installed
    case active
    case missing
    case corrupt
    case partial
}
