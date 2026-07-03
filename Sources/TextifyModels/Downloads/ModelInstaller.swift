import CryptoKit
import Foundation

public struct ModelInstaller {
    private let layout: ModelStorageLayout
    private let transport: any DownloadTransport
    private let fileManager: FileManager
    private let nowISO8601: @Sendable () -> String

    public init(
        layout: ModelStorageLayout,
        transport: any DownloadTransport,
        fileManager: FileManager = .default,
        nowISO8601: @escaping @Sendable () -> String = { ISO8601DateFormatter().string(from: Date()) }
    ) {
        self.layout = layout
        self.transport = transport
        self.fileManager = fileManager
        self.nowISO8601 = nowISO8601
    }

    public func install(modelID: String, from manifest: ModelManifest) async throws -> InstalledModelRecord {
        try ProductionModelPolicy.validateV1_1ProductionManifest(manifest)

        guard let model = manifest.models.first(where: { $0.id == modelID }) else {
            throw ModelInstallError.modelNotFound(modelID)
        }
        guard model.files.count == 1 else {
            throw ModelInstallError.expectedSingleFile(count: model.files.count)
        }
        let file = model.files[0]
        guard let url = URL(string: file.url) else {
            throw ModelInstallError.invalidDownloadURL(file.url)
        }

        try createDirectories()
        let temporaryURL = layout.temporaryDownloadURL(modelID: model.id, filename: file.filename)
        let installedURL = layout.installedFileURL(modelID: model.id, filename: file.filename)
        try? fileManager.removeItem(at: temporaryURL)

        _ = try await transport.downloadFile(URLRequest(url: url), to: temporaryURL)
        let actualChecksum = try sha256Hex(fileURL: temporaryURL)
        guard actualChecksum.lowercased() == file.sha256.lowercased() else {
            try? fileManager.removeItem(at: temporaryURL)
            throw ModelInstallError.checksumMismatch(expected: file.sha256, actual: actualChecksum)
        }

        try fileManager.createDirectory(
            at: layout.installedModelDirectory(modelID: model.id),
            withIntermediateDirectories: true
        )
        try? fileManager.removeItem(at: installedURL)
        try fileManager.moveItem(at: temporaryURL, to: installedURL)

        let record = InstalledModelRecord(
            model: model,
            installedAt: nowISO8601(),
            localFilesByManifestFilename: [file.filename: installedURL.path]
        )
        try upsertInstalledRecord(record)
        return record
    }

    private func createDirectories() throws {
        for directory in [
            layout.rootDirectory,
            layout.manifestsDirectory,
            layout.downloadsDirectory,
            layout.installedModelsDirectory
        ] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func upsertInstalledRecord(_ record: InstalledModelRecord) throws {
        var store = try loadStore()
        store.upsert(record)
        let data = try JSONEncoder().encode(store)
        try data.write(to: layout.installedStoreURL, options: [.atomic])
    }

    private func loadStore() throws -> InstalledModelsStore {
        guard fileManager.fileExists(atPath: layout.installedStoreURL.path) else {
            return InstalledModelsStore()
        }
        let data = try Data(contentsOf: layout.installedStoreURL)
        return try JSONDecoder().decode(InstalledModelsStore.self, from: data)
    }

    private func sha256Hex(fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
