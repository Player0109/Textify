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

    func testRemovalKeepsReceiptUntilManagedBytesAreGone() throws {
        let fixture = try removalFixture(modelID: "receipt-order")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let fileManager = RemovalFaultFileManager()
        fileManager.beforeRemove = {
            let persisted = try JSONDecoder().decode(
                InstalledModelsStore.self,
                from: Data(contentsOf: fixture.layout.installedStoreURL)
            )
            XCTAssertNotNil(
                persisted.record(forModelID: fixture.model.id),
                "The Installation Receipt must own bytes until filesystem removal succeeds."
            )
        }

        _ = try InstalledModelManager(
            layout: fixture.layout,
            fileManager: fileManager
        ).remove(modelID: fixture.model.id)

        XCTAssertEqual(fileManager.removeCallCount, 1)
        XCTAssertNil(
            try loadStore(fixture.layout).record(forModelID: fixture.model.id)
        )
    }

    func testRenameFailureLeavesInstalledBytesAndReceiptForRetry() throws {
        let fixture = try removalFixture(modelID: "rename-failure")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let fileManager = RemovalFaultFileManager()
        fileManager.moveError = CocoaError(.fileWriteNoPermission)

        XCTAssertThrowsError(
            try InstalledModelManager(
                layout: fixture.layout,
                fileManager: fileManager
            ).remove(modelID: fixture.model.id)
        ) { error in
            XCTAssertEqual(
                error as? InstalledModelManagerError,
                .filesystemOperationFailed(
                    modelID: fixture.model.id,
                    stage: .rename
                )
            )
        }

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.installedDirectory.path
            )
        )
        XCTAssertNotNil(
            try loadStore(fixture.layout).record(forModelID: fixture.model.id)
        )
    }

    func testPermissionFailureDuringRemovalRetainsDiagnosableOwnership() throws {
        let fixture = try removalFixture(modelID: "permission-failure")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let fileManager = RemovalFaultFileManager()
        fileManager.removeError = CocoaError(.fileWriteNoPermission)

        XCTAssertThrowsError(
            try InstalledModelManager(
                layout: fixture.layout,
                fileManager: fileManager
            ).remove(modelID: fixture.model.id)
        ) { error in
            XCTAssertEqual(
                error as? InstalledModelManagerError,
                .filesystemOperationFailed(
                    modelID: fixture.model.id,
                    stage: .removeManagedBytes
                )
            )
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.installedDirectory.path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: try fixture.layout.pendingRemovalDirectory(
                    modelID: fixture.model.id
                ).path
            )
        )
        XCTAssertNotNil(
            try loadStore(fixture.layout).record(forModelID: fixture.model.id)
        )
    }

    func testPartialRemovalCanResumeAfterRelaunchWithoutClaimingEarlySuccess() throws {
        let fixture = try removalFixture(
            modelID: "partial-removal",
            filenames: ["first.bin", "second.bin"]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let fileManager = RemovalFaultFileManager()
        fileManager.partiallyRemoveThenFail = true
        let firstManager = InstalledModelManager(
            layout: fixture.layout,
            fileManager: fileManager
        )

        XCTAssertThrowsError(
            try firstManager.remove(modelID: fixture.model.id)
        )
        XCTAssertNotNil(
            try loadStore(fixture.layout).record(forModelID: fixture.model.id)
        )
        let pendingDirectory = try fixture.layout.pendingRemovalDirectory(
            modelID: fixture.model.id
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: pendingDirectory.path)
        )

        let relaunchedManager = InstalledModelManager(layout: fixture.layout)
        _ = try relaunchedManager.remove(modelID: fixture.model.id)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: pendingDirectory.path)
        )
        XCTAssertNil(
            try loadStore(fixture.layout).record(forModelID: fixture.model.id)
        )
    }

    func testMissingInstalledDirectoryStillRemovesReceipt() throws {
        let fixture = try removalFixture(modelID: "missing-files")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try FileManager.default.removeItem(at: fixture.installedDirectory)

        _ = try InstalledModelManager(layout: fixture.layout).remove(
            modelID: fixture.model.id
        )

        XCTAssertNil(
            try loadStore(fixture.layout).record(forModelID: fixture.model.id)
        )
    }

    private func removalFixture(
        modelID: String,
        filenames: [String] = ["model.ggml"]
    ) throws -> (
        root: URL,
        layout: ModelStorageLayout,
        model: ModelEntry,
        installedDirectory: URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TextifyModelRemoval-\(UUID().uuidString)",
                isDirectory: true
            )
        let layout = ModelStorageLayout(rootDirectory: root)
        let source = try fixtureModel(id: modelID)
        let files = filenames.map {
            ModelFile(
                filename: $0,
                url: "https://example.com/\($0)",
                sha256: String(repeating: "a", count: 64),
                sizeBytes: 5
            )
        }
        let model = ModelEntry(
            id: source.id,
            displayName: source.displayName,
            tier: source.tier,
            description: source.description,
            sizeBytes: Int64(files.count * 5),
            files: files,
            licenses: source.licenses,
            provenance: source.provenance,
            runtimeParameters: source.runtimeParameters,
            hallucinationThresholds: source.hallucinationThresholds,
            minAppVersion: source.minAppVersion,
            runtime: source.runtime,
            capabilities: source.capabilities
        )
        let installedDirectory = try layout.installedModelDirectory(
            modelID: model.id
        )
        try FileManager.default.createDirectory(
            at: installedDirectory,
            withIntermediateDirectories: true
        )
        var localFiles: [String: String] = [:]
        for filename in filenames {
            let fileURL = installedDirectory.appendingPathComponent(filename)
            try Data("model".utf8).write(to: fileURL)
            localFiles[filename] = fileURL.path
        }
        let store = InstalledModelsStore(records: [
            InstalledModelRecord(
                model: model,
                installedAt: "2026-07-24T00:00:00Z",
                localFilesByManifestFilename: localFiles
            ),
        ])
        try JSONEncoder().encode(store).write(
            to: layout.installedStoreURL,
            options: .atomic
        )
        return (root, layout, model, installedDirectory)
    }

    private func loadStore(
        _ layout: ModelStorageLayout
    ) throws -> InstalledModelsStore {
        try JSONDecoder().decode(
            InstalledModelsStore.self,
            from: Data(contentsOf: layout.installedStoreURL)
        )
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

private final class RemovalFaultFileManager: FileManager, @unchecked Sendable {
    var moveError: Error?
    var removeError: Error?
    var partiallyRemoveThenFail = false
    var beforeRemove: (() throws -> Void)?
    private(set) var removeCallCount = 0

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if let moveError {
            throw moveError
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }

    override func removeItem(at URL: URL) throws {
        removeCallCount += 1
        try beforeRemove?()
        if partiallyRemoveThenFail {
            partiallyRemoveThenFail = false
            let firstChild = try contentsOfDirectory(
                at: URL,
                includingPropertiesForKeys: nil
            ).first
            if let firstChild {
                try super.removeItem(at: firstChild)
            }
            throw CocoaError(.fileWriteNoPermission)
        }
        if let removeError {
            throw removeError
        }
        try super.removeItem(at: URL)
    }
}
