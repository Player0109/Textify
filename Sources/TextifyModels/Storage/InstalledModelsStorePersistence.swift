import Foundation

public struct InstalledModelsStorePersistence: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager
    private let durabilityObserver: ModelWorkflowDurabilityObserver

    public init(
        fileURL: URL,
        fileManager: FileManager = .default,
        durabilityObserver: ModelWorkflowDurabilityObserver = .none
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.durabilityObserver = durabilityObserver
    }

    public func load() throws -> InstalledModelsStore {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return InstalledModelsStore()
        }
        return try JSONDecoder().decode(
            InstalledModelsStore.self,
            from: Data(contentsOf: fileURL)
        )
    }

    @discardableResult
    public func persistInstallation(
        _ record: InstalledModelRecord
    ) throws -> InstalledModelsStore {
        var store = try load()
        store.upsert(record)
        try persist(
            store,
            boundary: .installationReceiptPersisted,
            artifactID: record.model.id
        )
        return store
    }

    public func persistRestorationAcknowledgment(
        _ store: InstalledModelsStore,
        artifactID: String
    ) throws {
        try persist(
            store,
            boundary: .restorationIntegrityAcknowledged,
            artifactID: artifactID
        )
    }

    public func persistReconciliation(
        _ store: InstalledModelsStore
    ) throws {
        try persist(
            store,
            boundary: .reconciliationReceiptPersisted,
            artifactID: nil
        )
    }

    public func persistDeletion(
        _ store: InstalledModelsStore,
        artifactID: String
    ) throws {
        try persist(
            store,
            boundary: .deletionReceiptRemoved,
            artifactID: artifactID
        )
    }

    private func persist(
        _ store: InstalledModelsStore,
        boundary: ModelWorkflowDurableBoundary,
        artifactID: String?
    ) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(store).write(
            to: fileURL,
            options: .atomic
        )
        try durabilityObserver.didReach(
            boundary,
            artifactID: artifactID
        )
    }
}
