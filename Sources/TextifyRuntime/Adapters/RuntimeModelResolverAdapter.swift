import CryptoKit
import Foundation
import TextifyModels
import TextifySettings

public actor RuntimeModelResolverAdapter: RuntimeModelResolving {
    private let layout: ModelStorageLayout
    private let loadStore: @Sendable () throws -> InstalledModelsStore

    public init(
        layout: ModelStorageLayout,
        loadStore: @escaping @Sendable () throws -> InstalledModelsStore
    ) {
        self.layout = layout
        self.loadStore = loadStore
    }

    public init(layout: ModelStorageLayout) {
        self.init(layout: layout) {
            try Self.loadInstalledStore(layout: layout)
        }
    }

    public func resolveActiveModel(preferences: AppPreferences) async -> RuntimeActiveModel? {
        guard preferences.modelSelectionScope == .curatedInstalledModels,
              let modelID = preferences.activeModelID,
              let record = try? loadStore().record(forModelID: modelID),
              let firstFile = record.model.files.first,
              let canonicalURL = try? layout.installedFileURL(
                  modelID: record.model.id,
                  filename: firstFile.filename
              ),
              record.localFilesByManifestFilename[firstFile.filename] == canonicalURL.path
        else {
            return nil
        }

        return RuntimeActiveModel(
            id: record.model.id,
            displayName: record.model.displayName,
            tier: record.model.tier,
            localModelPath: canonicalURL.path,
            useGPU: true,
            threadCount: ProcessInfo.processInfo.activeProcessorCount
        )
    }

    public func readiness(for model: RuntimeActiveModel?) async -> RuntimeModelReadiness {
        guard let model else {
            return .noActiveModel
        }

        guard let installedFile = installedFile(for: model) else {
            return .missing(modelID: model.id)
        }
        guard FileManager.default.fileExists(atPath: installedFile.url.path) else {
            return .missing(modelID: model.id)
        }
        guard installedFile.url.path == model.localModelPath,
              fileSize(at: installedFile.url) == installedFile.manifestFile.sizeBytes,
              (try? Self.sha256Hex(fileURL: installedFile.url)) == installedFile.manifestFile.sha256
        else {
            return .failed(modelID: model.id, reason: .checksumFailed)
        }

        return .ready(modelID: model.id)
    }

    private static func loadInstalledStore(layout: ModelStorageLayout) throws -> InstalledModelsStore {
        guard FileManager.default.fileExists(atPath: layout.installedStoreURL.path) else {
            return InstalledModelsStore()
        }

        let data = try Data(contentsOf: layout.installedStoreURL)
        return try JSONDecoder().decode(InstalledModelsStore.self, from: data)
    }

    private func installedFile(for model: RuntimeActiveModel) -> InstalledFile? {
        guard let record = try? loadStore().record(forModelID: model.id),
              let manifestFile = record.model.files.first,
              let canonicalURL = try? layout.installedFileURL(
                  modelID: record.model.id,
                  filename: manifestFile.filename
              ),
              record.localFilesByManifestFilename[manifestFile.filename] == canonicalURL.path
        else {
            return nil
        }

        return InstalledFile(url: canonicalURL, manifestFile: manifestFile)
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let fileSize = try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? NSNumber
        else {
            return nil
        }
        return fileSize.int64Value
    }

    private static func sha256Hex(fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private struct InstalledFile {
        let url: URL
        let manifestFile: ModelFile
    }
}
