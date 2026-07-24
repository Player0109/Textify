import Foundation

public enum InstalledModelRemovalStage: String, Equatable, Sendable {
    case prepare
    case rename
    case removeManagedBytes
    case persistReceipt
}

public enum InstalledModelManagerError: Error, Equatable, LocalizedError {
    case modelNotInstalled(String)
    case filesystemOperationFailed(
        modelID: String,
        stage: InstalledModelRemovalStage
    )

    public var errorDescription: String? {
        switch self {
        case let .modelNotInstalled(modelID):
            return "\(modelID) is not installed."
        case let .filesystemOperationFailed(modelID, stage):
            switch stage {
            case .prepare:
                return "Textify could not prepare \(modelID) for deletion. No model data was removed."
            case .rename:
                return "Textify could not begin deleting \(modelID). Its Installation Receipt and model data were kept."
            case .removeManagedBytes:
                return "Textify could not finish deleting \(modelID). Its Installation Receipt and remaining model data were kept so you can retry."
            case .persistReceipt:
                return "Textify removed the managed bytes for \(modelID), but could not update its Installation Receipt. Retry to finish."
            }
        }
    }
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
        let store = try loadStore()
        guard let record = store.record(forModelID: modelID) else {
            throw InstalledModelManagerError.modelNotInstalled(modelID)
        }

        let installedDirectory = try layout.installedModelDirectory(
            modelID: record.storageModelID
        )
        let removalDirectory = try layout.pendingRemovalDirectory(
            modelID: record.storageModelID
        )
        do {
            try fileManager.createDirectory(
                at: layout.downloadsDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw InstalledModelManagerError.filesystemOperationFailed(
                modelID: modelID,
                stage: .prepare
            )
        }

        let hasInstalledDirectory = fileManager.fileExists(
            atPath: installedDirectory.path
        )
        let hasPendingRemoval = fileManager.fileExists(
            atPath: removalDirectory.path
        )
        if hasInstalledDirectory && hasPendingRemoval {
            throw InstalledModelManagerError.filesystemOperationFailed(
                modelID: modelID,
                stage: .rename
            )
        }
        if hasInstalledDirectory {
            do {
                try fileManager.moveItem(
                    at: installedDirectory,
                    to: removalDirectory
                )
            } catch {
                throw InstalledModelManagerError.filesystemOperationFailed(
                    modelID: modelID,
                    stage: .rename
                )
            }
        }

        if fileManager.fileExists(atPath: removalDirectory.path) {
            do {
                try fileManager.removeItem(at: removalDirectory)
            } catch {
                throw InstalledModelManagerError.filesystemOperationFailed(
                    modelID: modelID,
                    stage: .removeManagedBytes
                )
            }
        }

        var updatedStore = store
        _ = updatedStore.remove(modelID: modelID)
        do {
            try JSONEncoder().encode(updatedStore).write(
                to: layout.installedStoreURL,
                options: [.atomic]
            )
        } catch {
            throw InstalledModelManagerError.filesystemOperationFailed(
                modelID: modelID,
                stage: .persistReceipt
            )
        }
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
