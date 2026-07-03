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

        let installedURL = layout.installedFileURL(modelID: model.id, filename: file.filename)
        XCTAssertEqual(record.model.id, ProductionModelPolicy.requiredModelID)
        XCTAssertEqual(record.localFilesByManifestFilename[file.filename], installedURL.path)
        XCTAssertEqual(try Data(contentsOf: installedURL), modelData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.temporaryDownloadURL(modelID: model.id, filename: file.filename).path))

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

        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.temporaryDownloadURL(modelID: model.id, filename: file.filename).path))
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

    private static func fixtureManifest(replacingModelID modelID: String? = nil) throws -> ModelManifest {
        let manifest = try ModelManifest.decode(try fixtureData("manifest.json"))
        guard let modelID else {
            return manifest
        }

        let models = manifest.models.map { model -> ModelEntry in
            ModelEntry(
                id: modelID,
                displayName: model.displayName,
                tier: model.tier,
                description: model.description,
                sizeBytes: model.sizeBytes,
                files: model.files,
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
