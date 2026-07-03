import Foundation

public struct InstalledModelRecord: Codable, Equatable {
    public let model: ModelEntry
    public let installedAt: String
    public let localFilesByManifestFilename: [String: String]

    public init(
        model: ModelEntry,
        installedAt: String,
        localFilesByManifestFilename: [String: String]
    ) {
        self.model = model
        self.installedAt = installedAt
        self.localFilesByManifestFilename = localFilesByManifestFilename
    }
}

public struct InstalledModelsStore: Codable, Equatable {
    public private(set) var records: [InstalledModelRecord]

    public init(records: [InstalledModelRecord] = []) {
        self.records = records
    }

    public func record(forModelID modelID: String) -> InstalledModelRecord? {
        records.first { $0.model.id == modelID }
    }

    public mutating func upsert(_ record: InstalledModelRecord) {
        records.removeAll { $0.model.id == record.model.id }
        records.append(record)
    }

    @discardableResult
    public mutating func remove(modelID: String) -> InstalledModelRecord? {
        guard let index = records.firstIndex(where: { $0.model.id == modelID }) else {
            return nil
        }
        return records.remove(at: index)
    }
}
