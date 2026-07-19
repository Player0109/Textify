import Foundation

public enum InstalledModelManagerError: Error, Equatable {
    case modelNotInstalled(String)
}

public struct InstalledModelManager: @unchecked Sendable {
    private let layout: ModelStorageLayout
    private let fileManager: FileManager

    public init(
        layout: ModelStorageLayout,
        fileManager: FileManager = .default
    ) {
        self.layout = layout
        self.fileManager = fileManager
    }

    @discardableResult
    public func remove(modelID: String) throws -> InstalledModelRecord {
        var store = try loadStore()
        guard let record = store.remove(modelID: modelID) else {
            throw InstalledModelManagerError.modelNotInstalled(modelID)
        }

        try fileManager.createDirectory(
            at: layout.downloadsDirectory,
            withIntermediateDirectories: true
        )
        let installedDirectory = try layout.installedModelDirectory(modelID: modelID)
        let removalDirectory = try layout.temporaryRemovalDirectory(modelID: modelID)
        let hadInstalledDirectory = fileManager.fileExists(atPath: installedDirectory.path)
        if hadInstalledDirectory {
            try fileManager.moveItem(at: installedDirectory, to: removalDirectory)
        }

        do {
            try JSONEncoder().encode(store).write(
                to: layout.installedStoreURL,
                options: [.atomic]
            )
        } catch {
            if hadInstalledDirectory,
               fileManager.fileExists(atPath: removalDirectory.path) {
                try? fileManager.moveItem(at: removalDirectory, to: installedDirectory)
            }
            throw error
        }

        try? fileManager.removeItem(at: removalDirectory)
        return record
    }

    private func loadStore() throws -> InstalledModelsStore {
        guard fileManager.fileExists(atPath: layout.installedStoreURL.path) else {
            return InstalledModelsStore()
        }
        return try JSONDecoder().decode(
            InstalledModelsStore.self,
            from: Data(contentsOf: layout.installedStoreURL)
        )
    }
}
