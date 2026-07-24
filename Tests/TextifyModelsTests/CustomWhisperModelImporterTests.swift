import CryptoKit
import Foundation
import TextifyModels
import XCTest

final class CustomWhisperModelImporterTests: XCTestCase {
    func testImporterValidatesCopiesAndRecordsWhisperModel() async throws {
        let root = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("source-model.bin")
        var modelData = Data([0x6c, 0x6d, 0x67, 0x67])
        modelData.append(Data(repeating: 0x5a, count: 1_048_572))
        try modelData.write(to: sourceURL)
        let layout = ModelStorageLayout(rootDirectory: root.appendingPathComponent("models"))
        let importer = CustomWhisperModelImporter(
            layout: layout,
            nowISO8601: { "2026-07-19T00:00:00Z" }
        )

        let record = try await importer.importModel(
            from: sourceURL,
            options: CustomWhisperImportOptions(
                displayName: "My Whisper Model",
                licenseName: "User confirmed model license"
            )
        )

        let checksum = SHA256.hash(data: modelData)
            .map { String(format: "%02x", $0) }
            .joined()
        XCTAssertEqual(
            record.model.id,
            CustomWhisperModelImporter.importedModelIDPrefix + checksum
        )
        XCTAssertEqual(record.model.runtime.engine, .whisperCpp)
        XCTAssertEqual(record.model.runtime.accelerator, .metalGPU)
        XCTAssertEqual(record.model.capabilities.languages, ["*"])
        XCTAssertEqual(record.model.licenses.first?.spdxId, "NOASSERTION")
        let installedURL = try XCTUnwrap(
            record.localFilesByManifestFilename[record.model.files[0].filename]
        )
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: installedURL)), modelData)
        let store = try JSONDecoder().decode(
            InstalledModelsStore.self,
            from: Data(contentsOf: layout.installedStoreURL)
        )
        XCTAssertEqual(store.record(forModelID: record.model.id), record)
    }

    func testImporterRejectsUnrecognizedHeaderWithoutCreatingStore() async throws {
        let root = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("not-a-model.bin")
        try Data(repeating: 0, count: 1_048_576).write(to: sourceURL)
        let layout = ModelStorageLayout(rootDirectory: root.appendingPathComponent("models"))
        let importer = CustomWhisperModelImporter(layout: layout)

        do {
            _ = try await importer.importModel(
                from: sourceURL,
                options: CustomWhisperImportOptions(
                    displayName: "Invalid",
                    licenseName: "User confirmed model license"
                )
            )
            XCTFail("Expected unsupported header")
        } catch let error as CustomWhisperModelImportError {
            XCTAssertEqual(error, .unsupportedFileHeader)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.installedStoreURL.path))
    }

    func testDuplicateImportReusesFullDigestIdentityAndPreservesRenameHistory() async throws {
        let root = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("renamed-model.bin")
        var modelData = Data([0x6c, 0x6d, 0x67, 0x67])
        modelData.append(Data(repeating: 0x41, count: 1_048_572))
        try modelData.write(to: sourceURL)
        let layout = ModelStorageLayout(rootDirectory: root.appendingPathComponent("models"))
        let importer = CustomWhisperModelImporter(
            layout: layout,
            nowISO8601: { "2026-07-24T00:00:00Z" }
        )

        _ = try await importer.importModel(
            from: sourceURL,
            options: CustomWhisperImportOptions(
                displayName: "Original Local Name",
                licenseName: "User-provided model; license not verified by Textify"
            )
        )
        let renamed = try await importer.importModel(
            from: sourceURL,
            options: CustomWhisperImportOptions(
                displayName: "Renamed Local Model",
                licenseName: "User-provided model; license not verified by Textify"
            )
        )

        let checksum = SHA256.hash(data: modelData)
            .map { String(format: "%02x", $0) }
            .joined()
        XCTAssertEqual(renamed.model.id, "custom-sha256-\(checksum)")
        XCTAssertEqual(renamed.model.displayName, "Renamed Local Model")
        XCTAssertNil(renamed.model.benchmark)
        XCTAssertEqual(renamed.model.licenses.first?.spdxId, "NOASSERTION")
        XCTAssertEqual(
            renamed.identityHistory.customImport?.localNames,
            ["Original Local Name", "Renamed Local Model"]
        )

        let store = try JSONDecoder().decode(
            InstalledModelsStore.self,
            from: Data(contentsOf: layout.installedStoreURL)
        )
        XCTAssertEqual(store.records, [renamed])
        XCTAssertEqual(
            ModelArtifactPlacementResolver()
                .reconcile(records: store.records, trustedManifest: nil)
                .placement(forArtifactID: renamed.model.id),
            .custom
        )
    }

    func testImportDeduplicatesAgainstUniqueSignedDigestAndKeepsLocalHistory() async throws {
        let root = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("catalog-match.ggml")
        var modelData = Data([0x6c, 0x6d, 0x67, 0x67])
        modelData.append(Data(repeating: 0x34, count: 1_048_572))
        try modelData.write(to: sourceURL)
        let layout = ModelStorageLayout(rootDirectory: root.appendingPathComponent("models"))
        let firstImporter = CustomWhisperModelImporter(
            layout: layout,
            nowISO8601: { "2026-07-24T00:00:00Z" }
        )
        let local = try await firstImporter.importModel(
            from: sourceURL,
            options: CustomWhisperImportOptions(
                displayName: "Local Before Catalog",
                licenseName: "User-provided model; license not verified by Textify"
            )
        )
        let signed = copy(
            local.model,
            id: "signed-exact-artifact",
            displayName: "Signed Catalog Name"
        )
        let importer = CustomWhisperModelImporter(
            layout: layout,
            trustedManifest: ModelManifest(
                manifestVersion: 1,
                generatedAt: "2026-07-25T00:00:00Z",
                models: [signed]
            ),
            nowISO8601: { "2026-07-25T00:00:00Z" }
        )

        let canonical = try await importer.importModel(
            from: sourceURL,
            options: CustomWhisperImportOptions(
                displayName: "Renamed After Catalog",
                licenseName: "User-provided model; license not verified by Textify"
            )
        )

        XCTAssertEqual(canonical.model, signed)
        XCTAssertEqual(canonical.storageModelID, local.model.id)
        XCTAssertEqual(
            canonical.identityHistory.customImport?.localNames,
            ["Local Before Catalog", "Renamed After Catalog"]
        )
        let renamedCanonical = try await importer.importModel(
            from: sourceURL,
            options: CustomWhisperImportOptions(
                displayName: "Another Local Rename",
                licenseName: "User-provided model; license not verified by Textify"
            )
        )
        XCTAssertEqual(renamedCanonical.model, signed)
        XCTAssertEqual(
            renamedCanonical.identityHistory.customImport?.localNames,
            [
                "Local Before Catalog",
                "Renamed After Catalog",
                "Another Local Rename",
            ]
        )
        let store = try JSONDecoder().decode(
            InstalledModelsStore.self,
            from: Data(contentsOf: layout.installedStoreURL)
        )
        XCTAssertEqual(store.records, [renamedCanonical])
    }

    func testDuplicateImportMigratesUnresolvedLegacyIdentityToFullDigestNamespace() async throws {
        let root = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("legacy-import.ggml")
        var modelData = Data([0x6c, 0x6d, 0x67, 0x67])
        modelData.append(Data(repeating: 0x45, count: 1_048_572))
        try modelData.write(to: sourceURL)
        let layout = ModelStorageLayout(
            rootDirectory: root.appendingPathComponent("models")
        )
        let importer = CustomWhisperModelImporter(
            layout: layout,
            nowISO8601: { "2026-07-24T00:00:00Z" }
        )
        let custom = try await importer.importModel(
            from: sourceURL,
            options: CustomWhisperImportOptions(
                displayName: "Original Import",
                licenseName: "User-provided model; license not verified by Textify"
            )
        )
        let legacyStorageID = "legacy-storage"
        let customDirectory = try layout.installedModelDirectory(
            modelID: custom.storageModelID
        )
        let legacyDirectory = try layout.installedModelDirectory(
            modelID: legacyStorageID
        )
        try FileManager.default.moveItem(
            at: customDirectory,
            to: legacyDirectory
        )
        let filename = try XCTUnwrap(custom.model.files.first?.filename)
        let legacy = InstalledModelRecord(
            model: copy(
                custom.model,
                id: "legacy-arbitrary-id",
                displayName: "Legacy Local Name"
            ),
            installedAt: custom.installedAt,
            localFilesByManifestFilename: [
                filename: legacyDirectory.appendingPathComponent(filename).path,
            ],
            storageModelID: legacyStorageID,
            identityHistory: InstalledModelIdentityHistory()
        )
        try JSONEncoder().encode(
            InstalledModelsStore(records: [legacy])
        ).write(to: layout.installedStoreURL, options: [.atomic])

        let migrated = try await importer.importModel(
            from: sourceURL,
            options: CustomWhisperImportOptions(
                displayName: "Renamed Legacy Import",
                licenseName: "User-provided model; license not verified by Textify"
            )
        )

        XCTAssertEqual(migrated.model.id, custom.model.id)
        XCTAssertEqual(migrated.storageModelID, legacyStorageID)
        XCTAssertEqual(
            migrated.identityHistory.customImport?.localNames,
            ["Legacy Local Name", "Renamed Legacy Import"]
        )
        let store = try JSONDecoder().decode(
            InstalledModelsStore.self,
            from: Data(contentsOf: layout.installedStoreURL)
        )
        XCTAssertEqual(store.records, [migrated])
    }

    func testDuplicateImportReconcilesFullStoreWithoutDroppingCanonicalReceipt() async throws {
        let root = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("duplicate-receipt.ggml")
        var modelData = Data([0x6c, 0x6d, 0x67, 0x67])
        modelData.append(Data(repeating: 0x56, count: 1_048_572))
        try modelData.write(to: sourceURL)
        let layout = ModelStorageLayout(
            rootDirectory: root.appendingPathComponent("models")
        )
        let localImporter = CustomWhisperModelImporter(
            layout: layout,
            nowISO8601: { "2026-07-24T00:00:00Z" }
        )
        let custom = try await localImporter.importModel(
            from: sourceURL,
            options: CustomWhisperImportOptions(
                displayName: "Custom Receipt",
                licenseName: "User-provided model; license not verified by Textify"
            )
        )
        let signed = copy(
            custom.model,
            id: "signed-duplicate-receipt",
            displayName: "Signed Receipt"
        )
        let signedStorageID = "signed-storage"
        let signedDirectory = try layout.installedModelDirectory(
            modelID: signedStorageID
        )
        try FileManager.default.createDirectory(
            at: signedDirectory,
            withIntermediateDirectories: true
        )
        let filename = try XCTUnwrap(signed.files.first?.filename)
        let signedURL = signedDirectory.appendingPathComponent(filename)
        try modelData.write(to: signedURL)
        let signedRecord = InstalledModelRecord(
            model: signed,
            installedAt: "2026-07-23T00:00:00Z",
            localFilesByManifestFilename: [filename: signedURL.path],
            storageModelID: signedStorageID,
            identityHistory: InstalledModelIdentityHistory(wasCurated: true)
        )
        try JSONEncoder().encode(
            InstalledModelsStore(records: [custom, signedRecord])
        ).write(to: layout.installedStoreURL, options: [.atomic])
        let importer = CustomWhisperModelImporter(
            layout: layout,
            trustedManifest: ModelManifest(
                manifestVersion: 1,
                generatedAt: "2026-07-25T00:00:00Z",
                models: [signed]
            )
        )

        let imported = try await importer.importModel(
            from: sourceURL,
            options: CustomWhisperImportOptions(
                displayName: "Custom Receipt Rename",
                licenseName: "User-provided model; license not verified by Textify"
            )
        )

        XCTAssertEqual(imported.model.id, custom.model.id)
        let store = try JSONDecoder().decode(
            InstalledModelsStore.self,
            from: Data(contentsOf: layout.installedStoreURL)
        )
        XCTAssertEqual(
            Set(store.records.map(\.model.id)),
            [custom.model.id, signed.id]
        )
        XCTAssertEqual(
            Set(store.records.map(\.storageModelID)),
            [custom.storageModelID, signedStorageID]
        )
    }

    private func copy(
        _ model: ModelEntry,
        id: String,
        displayName: String
    ) -> ModelEntry {
        ModelEntry(
            id: id,
            displayName: displayName,
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
            installationStorage: model.installationStorage,
            benchmark: model.benchmark
        )
    }

    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyCustomWhisperTests-\(UUID().uuidString)", isDirectory: true)
    }
}
