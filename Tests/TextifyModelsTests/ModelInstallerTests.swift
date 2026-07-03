import Foundation
import TextifyModels
import XCTest

final class ModelInstallerTests: XCTestCase {
    func testProductionPolicyAcceptsFixtureManifest() throws {
        try ProductionModelPolicy.validateV1_1ProductionManifest(try Self.fixtureManifest())
    }

    func testProductionPolicyRejectsArbitraryModelImport() throws {
        let manifest = try Self.fixtureManifest(replacingModelID: "custom-local-model")

        XCTAssertThrowsError(try ProductionModelPolicy.validateV1_1ProductionManifest(manifest)) { error in
            XCTAssertEqual(error as? ProductionModelPolicyError, .wrongModelID("custom-local-model"))
        }
    }

    func testInstallerDownloadsVerifiesAndStoresModel() async throws {
        let manifest = try Self.fixtureManifest()
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let layout = ModelStorageLayout(rootDirectory: rootDirectory)
        let modelData = try Self.fixtureData("model.bin")
        let transport = FixtureFileDownloadTransport(dataByURL: [
            try XCTUnwrap(URL(string: file.url)): modelData
        ])
        let installer = ModelInstaller(
            layout: layout,
            transport: transport,
            nowISO8601: { "2026-07-03T00:00:00Z" }
        )

        let record = try await installer.install(modelID: ProductionModelPolicy.requiredModelID, from: manifest)

        let installedURL = try layout.installedFileURL(modelID: model.id, filename: file.filename)
        XCTAssertEqual(record.model.id, ProductionModelPolicy.requiredModelID)
        XCTAssertEqual(record.localFilesByManifestFilename[file.filename], installedURL.path)
        XCTAssertEqual(try Data(contentsOf: installedURL), modelData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try layout.temporaryDownloadURL(modelID: model.id, filename: file.filename).path))

        let storeData = try Data(contentsOf: layout.installedStoreURL)
        let store = try JSONDecoder().decode(InstalledModelsStore.self, from: storeData)
        XCTAssertEqual(store.record(forModelID: model.id)?.installedAt, "2026-07-03T00:00:00Z")
    }

    func testInstallerDeletesPartialOnChecksumMismatch() async throws {
        let manifest = try Self.fixtureManifest()
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let layout = ModelStorageLayout(rootDirectory: rootDirectory)
        let transport = FixtureFileDownloadTransport(dataByURL: [
            try XCTUnwrap(URL(string: file.url)): Data("wrong bytes".utf8)
        ])
        let installer = ModelInstaller(layout: layout, transport: transport)

        do {
            _ = try await installer.install(modelID: ProductionModelPolicy.requiredModelID, from: manifest)
            XCTFail("Expected checksum mismatch")
        } catch let error as ModelInstallError {
            switch error {
            case .checksumMismatch(expected: file.sha256, actual: _):
                break
            default:
                XCTFail("Unexpected install error: \(error)")
            }
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: try layout.temporaryDownloadURL(modelID: model.id, filename: file.filename).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.installedStoreURL.path))
    }

    func testInstallerRejectsArbitraryManifest() async throws {
        let manifest = try Self.fixtureManifest(replacingModelID: "custom-local-model")
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let transport = FixtureFileDownloadTransport(dataByURL: [
            try XCTUnwrap(URL(string: file.url)): try Self.fixtureData("model.bin")
        ])
        let installer = ModelInstaller(
            layout: ModelStorageLayout(rootDirectory: rootDirectory),
            transport: transport
        )

        do {
            _ = try await installer.install(modelID: model.id, from: manifest)
            XCTFail("Expected production policy to reject arbitrary model manifests")
        } catch let error as ProductionModelPolicyError {
            XCTAssertEqual(error, .wrongModelID("custom-local-model"))
        }
    }

    func testStorageLayoutRejectsTraversalModelID() throws {
        let layout = ModelStorageLayout(rootDirectory: Self.temporaryDirectory())

        XCTAssertThrowsError(try layout.installedModelDirectory(modelID: "../escape")) { error in
            XCTAssertEqual(error as? ModelStorageLayoutError, .unsafePathComponent("../escape"))
        }
    }

    func testInstallerRejectsTraversalFilename() async throws {
        let manifest = try Self.fixtureManifest(replacingFilename: "../model.bin")
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let installer = ModelInstaller(
            layout: ModelStorageLayout(rootDirectory: rootDirectory),
            transport: FixtureFileDownloadTransport(dataByURL: [:])
        )

        do {
            _ = try await installer.install(modelID: ProductionModelPolicy.requiredModelID, from: manifest)
            XCTFail("Expected unsafe filename rejection")
        } catch let error as ModelStorageLayoutError {
            XCTAssertEqual(error, .unsafePathComponent("../model.bin"))
        }
    }

    func testInstallerRejectsNonHTTPSModelFileURLBeforeDownload() async throws {
        let manifest = try Self.fixtureManifest(replacingFileURL: "http://github.com/Player0109/Textify/releases/download/models-v1/model.bin")
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let installer = ModelInstaller(
            layout: ModelStorageLayout(rootDirectory: rootDirectory),
            transport: FixtureFileDownloadTransport(dataByURL: [:])
        )

        do {
            _ = try await installer.install(modelID: ProductionModelPolicy.requiredModelID, from: manifest)
            XCTFail("Expected non-HTTPS model file URL rejection")
        } catch let error as ModelDownloadPolicyError {
            XCTAssertEqual(error, .nonHTTPSURL("http://github.com/Player0109/Textify/releases/download/models-v1/model.bin"))
        }
    }

    func testInstallerRejectsWrongModelFileHostBeforeDownload() async throws {
        let manifest = try Self.fixtureManifest(replacingFileURL: "https://example.com/Player0109/Textify/releases/download/models-v1/model.bin")
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let installer = ModelInstaller(
            layout: ModelStorageLayout(rootDirectory: rootDirectory),
            transport: FixtureFileDownloadTransport(dataByURL: [:])
        )

        do {
            _ = try await installer.install(modelID: ProductionModelPolicy.requiredModelID, from: manifest)
            XCTFail("Expected unsupported model file URL rejection")
        } catch let error as ModelDownloadPolicyError {
            XCTAssertEqual(error, .unsupportedModelFileURL("https://example.com/Player0109/Textify/releases/download/models-v1/model.bin"))
        }
    }

    func testExistingInstallUsesAtomicReplacementWithoutMovingInstalledFile() async throws {
        let manifest = try Self.fixtureManifest()
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let layout = ModelStorageLayout(rootDirectory: rootDirectory)
        let installedURL = try layout.installedFileURL(modelID: model.id, filename: file.filename)
        try FileManager.default.createDirectory(
            at: installedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existingData = Data("existing model bytes".utf8)
        try existingData.write(to: installedURL)
        let fileManager = InstalledPathRecordingFileManager(installedURL: installedURL)
        let fileReplacer = AtomicReplacementSpy(
            expectedInstalledURL: installedURL,
            expectedExistingData: existingData
        )
        let installer = ModelInstaller(
            layout: layout,
            transport: FixtureFileDownloadTransport(dataByURL: [
                try XCTUnwrap(URL(string: file.url)): try Self.fixtureData("model.bin")
            ]),
            fileManager: fileManager,
            fileReplacer: fileReplacer
        )

        _ = try await installer.install(modelID: ProductionModelPolicy.requiredModelID, from: manifest)

        XCTAssertEqual(fileReplacer.replacementCalls, 1)
        XCTAssertTrue(fileReplacer.installedFileExistedAtReplacement)
        XCTAssertEqual(fileReplacer.installedDataAtReplacement, existingData)
        XCTAssertFalse(fileManager.didMoveFromInstalledURL)
        XCTAssertFalse(fileManager.didMoveToInstalledURL)
        XCTAssertFalse(fileManager.didRemoveInstalledURL)
        XCTAssertEqual(try Data(contentsOf: installedURL), try Self.fixtureData("model.bin"))
    }

    func testExistingInstalledFileSurvivesFailedAtomicReplacement() async throws {
        let manifest = try Self.fixtureManifest()
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let layout = ModelStorageLayout(rootDirectory: rootDirectory)
        let installedURL = try layout.installedFileURL(modelID: model.id, filename: file.filename)
        try FileManager.default.createDirectory(
            at: installedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existingData = Data("existing model bytes".utf8)
        try existingData.write(to: installedURL)
        let fileReplacer = AtomicReplacementSpy(
            expectedInstalledURL: installedURL,
            expectedExistingData: existingData,
            injectedError: AtomicReplacementFailure.injected
        )
        let installer = ModelInstaller(
            layout: layout,
            transport: FixtureFileDownloadTransport(dataByURL: [
                try XCTUnwrap(URL(string: file.url)): try Self.fixtureData("model.bin")
            ]),
            fileReplacer: fileReplacer
        )

        do {
            _ = try await installer.install(modelID: ProductionModelPolicy.requiredModelID, from: manifest)
            XCTFail("Expected atomic replacement failure")
        } catch AtomicReplacementFailure.injected {
            // Expected injected filesystem failure.
        }

        XCTAssertEqual(fileReplacer.replacementCalls, 1)
        XCTAssertEqual(try Data(contentsOf: installedURL), existingData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.installedStoreURL.path))
    }

    private static func fixtureManifest(
        replacingModelID modelID: String? = nil,
        replacingFilename filename: String? = nil,
        replacingFileURL fileURL: String? = nil
    ) throws -> ModelManifest {
        let manifest = try ModelManifest.decode(try fixtureData("manifest.json"))
        guard modelID != nil || filename != nil || fileURL != nil else {
            return manifest
        }

        let models = manifest.models.map { model -> ModelEntry in
            let files = model.files.map { file in
                ModelFile(
                    filename: filename ?? file.filename,
                    url: fileURL ?? file.url,
                    sha256: file.sha256,
                    sizeBytes: file.sizeBytes
                )
            }
            return ModelEntry(
                id: modelID ?? model.id,
                displayName: model.displayName,
                tier: model.tier,
                description: model.description,
                sizeBytes: model.sizeBytes,
                files: files,
                licenses: model.licenses,
                provenance: model.provenance,
                runtimeParameters: model.runtimeParameters,
                hallucinationThresholds: model.hallucinationThresholds,
                minAppVersion: model.minAppVersion
            )
        }
        return ModelManifest(
            manifestVersion: manifest.manifestVersion,
            generatedAt: manifest.generatedAt,
            models: models
        )
    }

    private static func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: nil,
                subdirectory: "Fixtures/Models"
            )
        )
        return try Data(contentsOf: url)
    }

    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyModelsTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private final class FixtureFileDownloadTransport: DownloadTransport {
    private let dataByURL: [URL: Data]

    init(dataByURL: [URL: Data]) {
        self.dataByURL = dataByURL
    }

    func fetch(_ request: URLRequest) async throws -> DownloadResponse {
        guard let url = request.url, let data = dataByURL[url] else {
            throw FixtureFileDownloadTransportError.missingResponse
        }
        return DownloadResponse(data: data)
    }

    func downloadFile(_ request: URLRequest, to temporaryURL: URL) async throws -> DownloadFileResponse {
        let response = try await fetch(request)
        try response.data.write(to: temporaryURL)
        return DownloadFileResponse(fileURL: temporaryURL)
    }
}

private enum FixtureFileDownloadTransportError: Error {
    case missingResponse
}

private final class InstalledPathRecordingFileManager: FileManager {
    private let installedURL: URL
    private(set) var didMoveFromInstalledURL = false
    private(set) var didMoveToInstalledURL = false
    private(set) var didRemoveInstalledURL = false

    init(installedURL: URL) {
        self.installedURL = installedURL.standardizedFileURL
        super.init()
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if srcURL.standardizedFileURL == installedURL {
            didMoveFromInstalledURL = true
        }
        if dstURL.standardizedFileURL == installedURL {
            didMoveToInstalledURL = true
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }

    override func removeItem(at URL: URL) throws {
        if URL.standardizedFileURL == installedURL {
            didRemoveInstalledURL = true
        }
        try super.removeItem(at: URL)
    }
}

private final class AtomicReplacementSpy: InstalledModelFileReplacing {
    private let expectedInstalledURL: URL
    private let expectedExistingData: Data
    private let injectedError: (any Error)?
    private(set) var replacementCalls = 0
    private(set) var installedFileExistedAtReplacement = false
    private(set) var installedDataAtReplacement: Data?

    init(
        expectedInstalledURL: URL,
        expectedExistingData: Data,
        injectedError: (any Error)? = nil
    ) {
        self.expectedInstalledURL = expectedInstalledURL.standardizedFileURL
        self.expectedExistingData = expectedExistingData
        self.injectedError = injectedError
    }

    func replaceExistingInstalledFile(at installedURL: URL, with replacementURL: URL) throws {
        replacementCalls += 1
        XCTAssertEqual(installedURL.standardizedFileURL, expectedInstalledURL)
        installedFileExistedAtReplacement = FileManager.default.fileExists(atPath: installedURL.path)
        installedDataAtReplacement = try? Data(contentsOf: installedURL)
        XCTAssertEqual(installedDataAtReplacement, expectedExistingData)
        if let injectedError {
            throw injectedError
        }
        _ = try FileManager.default.replaceItemAt(
            installedURL,
            withItemAt: replacementURL,
            backupItemName: nil,
            options: []
        )
    }
}

private enum AtomicReplacementFailure: Error {
    case injected
}
