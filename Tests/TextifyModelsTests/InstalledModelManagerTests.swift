import Foundation
@testable import TextifyModels
import XCTest

final class InstalledModelManagerTests: XCTestCase {
    func testRemoveAtomicallyUpdatesStoreAndDeletesManagedDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyModelRemoval-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = ModelStorageLayout(rootDirectory: root)
        let model = try fixtureModel(id: "custom-whisper-fixture")
        let installedDirectory = try layout.installedModelDirectory(modelID: model.id)
        try FileManager.default.createDirectory(
            at: installedDirectory,
            withIntermediateDirectories: true
        )
        try Data("model".utf8).write(
            to: installedDirectory.appendingPathComponent("model.ggml")
        )
        let store = InstalledModelsStore(records: [
            InstalledModelRecord(
                model: model,
                installedAt: "2026-07-19T00:00:00Z",
                localFilesByManifestFilename: ["model.ggml": "managed"]
            )
        ])
        try JSONEncoder().encode(store).write(to: layout.installedStoreURL, options: [.atomic])

        let removed = try InstalledModelManager(layout: layout).remove(modelID: model.id)

        XCTAssertEqual(removed.model.id, model.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installedDirectory.path))
        let updatedStore = try JSONDecoder().decode(
            InstalledModelsStore.self,
            from: Data(contentsOf: layout.installedStoreURL)
        )
        XCTAssertNil(updatedStore.record(forModelID: model.id))
    }

    func testRemoveRejectsUnknownModelWithoutTouchingStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyModelRemoval-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = ModelStorageLayout(rootDirectory: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let originalData = try JSONEncoder().encode(InstalledModelsStore())
        try originalData.write(to: layout.installedStoreURL)

        XCTAssertThrowsError(
            try InstalledModelManager(layout: layout).remove(modelID: "not-installed")
        ) { error in
            XCTAssertEqual(
                error as? InstalledModelManagerError,
                .modelNotInstalled("not-installed")
            )
        }
        XCTAssertEqual(try Data(contentsOf: layout.installedStoreURL), originalData)
    }

    func testRemoveCanonicalArtifactDeletesItsPreservedStorageIdentity() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyModelRemoval-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = ModelStorageLayout(rootDirectory: root)
        let model = try fixtureModel(id: "signed-canonical-artifact")
        let storageModelID = "custom-sha256-\(String(repeating: "a", count: 64))"
        let installedDirectory = try layout.installedModelDirectory(
            modelID: storageModelID
        )
        try FileManager.default.createDirectory(
            at: installedDirectory,
            withIntermediateDirectories: true
        )
        try Data("model".utf8).write(
            to: installedDirectory.appendingPathComponent("model.ggml")
        )
        let store = InstalledModelsStore(records: [
            InstalledModelRecord(
                model: model,
                installedAt: "2026-07-19T00:00:00Z",
                localFilesByManifestFilename: ["model.ggml": "managed"],
                storageModelID: storageModelID,
                identityHistory: InstalledModelIdentityHistory(
                    customImport: CustomModelImportHistory(
                        contentDigest: ModelArtifactTypedDigest(
                            type: .singleFileSHA256,
                            value: String(repeating: "a", count: 64)
                        ),
                        localNames: ["Local import"],
                        sourceFilenames: ["local.ggml"]
                    )
                )
            ),
        ])
        try JSONEncoder().encode(store).write(
            to: layout.installedStoreURL,
            options: [.atomic]
        )

        let removed = try InstalledModelManager(layout: layout).remove(
            modelID: model.id
        )

        XCTAssertEqual(removed.storageModelID, storageModelID)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: installedDirectory.path)
        )
        let updatedStore = try JSONDecoder().decode(
            InstalledModelsStore.self,
            from: Data(contentsOf: layout.installedStoreURL)
        )
        XCTAssertNil(updatedStore.record(forModelID: model.id))
    }

    private func fixtureModel(id: String) throws -> ModelEntry {
        let data = try XCTUnwrap(
            Bundle.module.url(
                forResource: "manifest.json",
                withExtension: nil,
                subdirectory: "Fixtures/Models"
            )
        )
        let manifest = try JSONDecoder().decode(
            ModelManifest.self,
            from: Data(contentsOf: data)
        )
        let source = try XCTUnwrap(manifest.models.first)
        return ModelEntry(
            id: id,
            displayName: source.displayName,
            tier: source.tier,
            description: source.description,
            sizeBytes: source.sizeBytes,
            files: source.files,
            licenses: source.licenses,
            provenance: source.provenance,
            runtimeParameters: source.runtimeParameters,
            hallucinationThresholds: source.hallucinationThresholds,
            minAppVersion: source.minAppVersion,
            runtime: source.runtime,
            capabilities: source.capabilities
        )
    }
}
