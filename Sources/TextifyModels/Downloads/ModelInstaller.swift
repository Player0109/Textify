import CryptoKit
import Foundation

public protocol InstalledModelFileReplacing {
    func replaceExistingInstalledFile(at installedURL: URL, with replacementURL: URL) throws
}

public struct FileManagerInstalledModelFileReplacer: InstalledModelFileReplacing {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func replaceExistingInstalledFile(at installedURL: URL, with replacementURL: URL) throws {
        _ = try fileManager.replaceItemAt(
            installedURL,
            withItemAt: replacementURL,
            backupItemName: nil,
            options: []
        )
    }
}

public struct ModelInstaller {
    private let layout: ModelStorageLayout
    private let transport: any DownloadTransport
    private let fileManager: FileManager
    private let fileReplacer: any InstalledModelFileReplacing
    private let nowISO8601: @Sendable () -> String

    public init(
        layout: ModelStorageLayout,
        transport: any DownloadTransport,
        fileManager: FileManager = .default,
        fileReplacer: (any InstalledModelFileReplacing)? = nil,
        nowISO8601: @escaping @Sendable () -> String = { ISO8601DateFormatter().string(from: Date()) }
    ) {
        self.layout = layout
        self.transport = transport
        self.fileManager = fileManager
        self.fileReplacer = fileReplacer ?? FileManagerInstalledModelFileReplacer(fileManager: fileManager)
        self.nowISO8601 = nowISO8601
    }

    public func install(
        modelID: String,
        from manifest: ModelManifest,
        onStateChange: @escaping @Sendable (DownloadState) -> Void = { _ in }
    ) async throws -> InstalledModelRecord {
        do {
            return try await installReportingFailures(
                modelID: modelID,
                from: manifest,
                onStateChange: onStateChange
            )
        } catch {
            onStateChange(DownloadState(
                modelID: modelID,
                phase: .failed,
                message: String(describing: error)
            ))
            throw error
        }
    }

    private func installReportingFailures(
        modelID: String,
        from manifest: ModelManifest,
        onStateChange: @escaping @Sendable (DownloadState) -> Void
    ) async throws -> InstalledModelRecord {
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
        try ModelDownloadURLPolicy.requireTextifyGitHubReleaseAsset(url)

        try createDirectories()
        let installedModelDirectory = try layout.installedModelDirectory(modelID: model.id)
        let temporaryURL = try layout.temporaryDownloadURL(modelID: model.id, filename: file.filename)
        let installedURL = try layout.installedFileURL(modelID: model.id, filename: file.filename)
        let replacementURL = try layout.replacementFileURL(modelID: model.id, filename: file.filename)
        try? fileManager.removeItem(at: temporaryURL)
        try? fileManager.removeItem(at: replacementURL)

        onStateChange(DownloadState(
            modelID: model.id,
            phase: .checkingSpace,
            totalBytes: file.sizeBytes,
            message: "Preparing model download."
        ))
        onStateChange(DownloadState(
            modelID: model.id,
            phase: .downloading,
            totalBytes: file.sizeBytes,
            message: "Downloading model."
        ))
        _ = try await transport.downloadFile(URLRequest(url: url), to: temporaryURL) { progress in
            onStateChange(DownloadState(
                modelID: model.id,
                phase: .downloading,
                bytesDownloaded: progress.bytesDownloaded,
                totalBytes: progress.totalBytes > 0 ? progress.totalBytes : file.sizeBytes,
                message: "Downloading model."
            ))
        }
        onStateChange(DownloadState(
            modelID: model.id,
            phase: .verifying,
            bytesDownloaded: file.sizeBytes,
            totalBytes: file.sizeBytes,
            message: "Verifying model."
        ))
        let actualChecksum = try sha256Hex(fileURL: temporaryURL)
        guard actualChecksum.lowercased() == file.sha256.lowercased() else {
            try? fileManager.removeItem(at: temporaryURL)
            throw ModelInstallError.checksumMismatch(expected: file.sha256, actual: actualChecksum)
        }

        onStateChange(DownloadState(
            modelID: model.id,
            phase: .installing,
            bytesDownloaded: file.sizeBytes,
            totalBytes: file.sizeBytes,
            message: "Installing model."
        ))
        try fileManager.createDirectory(
            at: installedModelDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: temporaryURL, to: replacementURL)
        do {
            try replaceInstalledFile(
                replacementURL: replacementURL,
                installedURL: installedURL
            )
        } catch {
            try? fileManager.removeItem(at: replacementURL)
            throw error
        }

        let record = InstalledModelRecord(
            model: model,
            installedAt: nowISO8601(),
            localFilesByManifestFilename: [file.filename: installedURL.path]
        )
        try upsertInstalledRecord(record)
        onStateChange(DownloadState(
            modelID: model.id,
            phase: .installed,
            bytesDownloaded: file.sizeBytes,
            totalBytes: file.sizeBytes,
            message: "Model installed and verified."
        ))
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

    private func replaceInstalledFile(
        replacementURL: URL,
        installedURL: URL
    ) throws {
        guard fileManager.fileExists(atPath: installedURL.path) else {
            try fileManager.moveItem(at: replacementURL, to: installedURL)
            return
        }

        try fileReplacer.replaceExistingInstalledFile(at: installedURL, with: replacementURL)
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
