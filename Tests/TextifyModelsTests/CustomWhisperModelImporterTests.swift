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
            CustomWhisperModelImporter.importedModelIDPrefix + String(checksum.prefix(16))
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

    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyCustomWhisperTests-\(UUID().uuidString)", isDirectory: true)
    }
}
