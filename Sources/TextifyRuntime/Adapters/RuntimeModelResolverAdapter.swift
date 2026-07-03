import Foundation
import TextifyModels
import TextifySettings

public actor RuntimeModelResolverAdapter: RuntimeModelResolving {
    private let loadStore: () throws -> InstalledModelsStore

    public init(
        layout: ModelStorageLayout,
        loadStore: @escaping () throws -> InstalledModelsStore
    ) {
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
              let localPath = record.localFilesByManifestFilename[firstFile.filename]
        else {
            return nil
        }

        return RuntimeActiveModel(
            id: record.model.id,
            displayName: record.model.displayName,
            tier: record.model.tier,
            localModelPath: localPath,
            useGPU: true,
            threadCount: ProcessInfo.processInfo.activeProcessorCount
        )
    }

    public func readiness(for model: RuntimeActiveModel?) async -> RuntimeModelReadiness {
        guard let model else {
            return .noActiveModel
        }

        return FileManager.default.fileExists(atPath: model.localModelPath)
            ? .ready(modelID: model.id)
            : .missing(modelID: model.id)
    }

    private static func loadInstalledStore(layout: ModelStorageLayout) throws -> InstalledModelsStore {
        guard FileManager.default.fileExists(atPath: layout.installedStoreURL.path) else {
            return InstalledModelsStore()
        }

        let data = try Data(contentsOf: layout.installedStoreURL)
        return try JSONDecoder().decode(InstalledModelsStore.self, from: data)
    }
}
