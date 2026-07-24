import Foundation

public enum ModelArtifactDigestType: String, Codable, Equatable, Sendable {
    case singleFileSHA256 = "single_file_sha256"
    case artifactFingerprintSHA256 = "artifact_fingerprint_sha256"
}

public struct ModelArtifactTypedDigest: Codable, Equatable, Hashable, Sendable {
    public let type: ModelArtifactDigestType
    public let value: String

    public init(type: ModelArtifactDigestType, value: String) {
        self.type = type
        self.value = value.lowercased()
    }
}

public struct CustomModelImportHistory: Codable, Equatable, Sendable {
    public let contentDigest: ModelArtifactTypedDigest
    public let localNames: [String]
    public let sourceFilenames: [String]

    public init(
        contentDigest: ModelArtifactTypedDigest,
        localNames: [String],
        sourceFilenames: [String]
    ) {
        self.contentDigest = contentDigest
        self.localNames = localNames
        self.sourceFilenames = sourceFilenames
    }
}

public struct InstalledModelIdentityHistory: Codable, Equatable, Sendable {
    public let wasCurated: Bool
    public let customImport: CustomModelImportHistory?

    public init(
        wasCurated: Bool = false,
        customImport: CustomModelImportHistory? = nil
    ) {
        self.wasCurated = wasCurated
        self.customImport = customImport
    }
}

public struct InstalledModelRecord: Codable, Equatable, Sendable {
    public let model: ModelEntry
    public let installedAt: String
    public let localFilesByManifestFilename: [String: String]
    public let storageModelID: String
    public let identityHistory: InstalledModelIdentityHistory

    public init(
        model: ModelEntry,
        installedAt: String,
        localFilesByManifestFilename: [String: String]
    ) {
        self.init(
            model: model,
            installedAt: installedAt,
            localFilesByManifestFilename: localFilesByManifestFilename,
            storageModelID: model.id,
            identityHistory: InstalledModelIdentityHistory()
        )
    }

    public init(
        model: ModelEntry,
        installedAt: String,
        localFilesByManifestFilename: [String: String],
        identityHistory: InstalledModelIdentityHistory
    ) {
        self.init(
            model: model,
            installedAt: installedAt,
            localFilesByManifestFilename: localFilesByManifestFilename,
            storageModelID: model.id,
            identityHistory: identityHistory
        )
    }

    public init(
        model: ModelEntry,
        installedAt: String,
        localFilesByManifestFilename: [String: String],
        storageModelID: String,
        identityHistory: InstalledModelIdentityHistory
    ) {
        self.model = model
        self.installedAt = installedAt
        self.localFilesByManifestFilename = localFilesByManifestFilename
        self.storageModelID = storageModelID
        self.identityHistory = identityHistory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(ModelEntry.self, forKey: .model)
        installedAt = try container.decode(String.self, forKey: .installedAt)
        localFilesByManifestFilename = try container.decode(
            [String: String].self,
            forKey: .localFilesByManifestFilename
        )
        storageModelID = try container.decodeIfPresent(
            String.self,
            forKey: .storageModelID
        ) ?? model.id
        identityHistory = try container.decodeIfPresent(
            InstalledModelIdentityHistory.self,
            forKey: .identityHistory
        ) ?? InstalledModelIdentityHistory()
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
