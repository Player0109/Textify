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
        self.records = Self.uniqueRecords(records)
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        records = try Self.uniqueRecords(
            container.decode([InstalledModelRecord].self, forKey: .records)
        )
    }

    private static func uniqueRecords(
        _ records: [InstalledModelRecord]
    ) -> [InstalledModelRecord] {
        var result: [InstalledModelRecord] = []
        for record in records {
            if let index = result.firstIndex(
                where: { $0.model.id == record.model.id }
            ) {
                result[index] = record
            } else {
                result.append(record)
            }
        }
        return result
    }
}
