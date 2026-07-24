import Foundation

public enum ModelArtifactPlacement: String, Codable, Equatable, Sendable {
    case curated
    case noLongerCurated
    case legacy
    case custom

    public var title: String {
        switch self {
        case .curated:
            "Curated"
        case .noLongerCurated:
            "No Longer Curated"
        case .legacy:
            "Legacy"
        case .custom:
            "Custom"
        }
    }
}

public struct ModelArtifactPlacementSnapshot: Equatable, Sendable {
    public let records: [InstalledModelRecord]
    private let placementsByArtifactID: [String: ModelArtifactPlacement]

    init(
        records: [InstalledModelRecord],
        placementsByArtifactID: [String: ModelArtifactPlacement]
    ) {
        self.records = records
        self.placementsByArtifactID = placementsByArtifactID
    }

    public func placement(forArtifactID artifactID: String) -> ModelArtifactPlacement? {
        placementsByArtifactID[artifactID]
    }
}

public struct ModelArtifactPlacementResolver: Sendable {
    public init() {}

    public func reconcile(
        records: [InstalledModelRecord],
        trustedManifest: ModelManifest?
    ) -> ModelArtifactPlacementSnapshot {
        let curatedModelsByID = trustedManifest?.models.reduce(
            into: [String: ModelEntry]()
        ) {
            $0[$1.id] = $1
        } ?? [:]
        let trustedModelsByDigest = Dictionary(
            grouping: trustedManifest?.models.flatMap { model in
                model.artifactTypedDigests().map { ($0, model) }
            } ?? [],
            by: \.0
        )
        let canonicalAliasByID = canonicalAliases(
            trustedManifest?.artifactAliases ?? []
        )
        let storedRecords = InstalledModelsStore(records: records).records
        let storedArtifactIDs = Set(storedRecords.map(\.model.id))
        let migratedRecords = storedRecords.map {
            migrateLegacyCustomIdentity(
                $0,
                occupiedArtifactIDs: storedArtifactIDs
            )
        }
        let localRecordCountByDigest = Dictionary(
            grouping: migratedRecords.flatMap { record in
                Set(contentDigests(for: record)).map { ($0, record.model.id) }
            },
            by: \.0
        ).mapValues(\.count)
        var placementsByArtifactID: [String: ModelArtifactPlacement] = [:]
        let reconciledRecords = migratedRecords.map { record in
            if let curatedModel = curatedModelsByID[record.model.id] {
                placementsByArtifactID[curatedModel.id] = .curated
                return InstalledModelRecord(
                    model: curatedModel,
                    installedAt: record.installedAt,
                    localFilesByManifestFilename: canonicalLocalFiles(
                        record: record,
                        canonicalModel: curatedModel
                    ),
                    storageModelID: record.storageModelID,
                    identityHistory: InstalledModelIdentityHistory(
                        wasCurated: true,
                        customImport: record.identityHistory.customImport
                    )
                )
            }
            if let canonicalModel = uniqueCanonicalModel(
                   for: record,
                    trustedModelsByDigest: trustedModelsByDigest,
                    canonicalAliasByID: canonicalAliasByID,
                    localRecordCountByDigest: localRecordCountByDigest
               ) {
                let localHistory = record.identityHistory.customImport
                    ?? contentDigests(for: record).first.map {
                        CustomModelImportHistory(
                            contentDigest: $0,
                            localNames: [record.model.displayName],
                            sourceFilenames: [record.model.provenance.sourceFile]
                        )
                    }
                let canonicalRecord = InstalledModelRecord(
                    model: canonicalModel,
                    installedAt: record.installedAt,
                    localFilesByManifestFilename: canonicalLocalFiles(
                        record: record,
                        canonicalModel: canonicalModel
                    ),
                    storageModelID: record.storageModelID,
                    identityHistory: InstalledModelIdentityHistory(
                        wasCurated: true,
                        customImport: localHistory
                    )
                )
                placementsByArtifactID[canonicalModel.id] = .curated
                return canonicalRecord
            }
            let wasCurated = record.identityHistory.wasCurated
            let placement: ModelArtifactPlacement = wasCurated
                ? .noLongerCurated
                : record.identityHistory.customImport == nil ? .legacy : .custom
            placementsByArtifactID[record.model.id] = placement
            return record
        }
        return ModelArtifactPlacementSnapshot(
            records: reconciledRecords,
            placementsByArtifactID: placementsByArtifactID
        )
    }

    private func migrateLegacyCustomIdentity(
        _ record: InstalledModelRecord,
        occupiedArtifactIDs: Set<String>
    ) -> InstalledModelRecord {
        guard record.identityHistory.customImport == nil,
              record.model.id.hasPrefix("custom-whisper-"),
              let digest = record.model.artifactTypedDigests().first,
              digest.type == .singleFileSHA256
        else {
            return record
        }
        let customID = CustomWhisperModelImporter.importedModelIDPrefix + digest.value
        guard !occupiedArtifactIDs.contains(customID) else {
            return record
        }
        return InstalledModelRecord(
            model: record.model.copying(id: customID),
            installedAt: record.installedAt,
            localFilesByManifestFilename: record.localFilesByManifestFilename,
            storageModelID: record.storageModelID,
            identityHistory: InstalledModelIdentityHistory(
                wasCurated: record.identityHistory.wasCurated,
                customImport: CustomModelImportHistory(
                    contentDigest: digest,
                    localNames: [record.model.displayName],
                    sourceFilenames: [record.model.provenance.sourceFile]
                )
            )
        )
    }

    private func uniqueCanonicalModel(
        for record: InstalledModelRecord,
        trustedModelsByDigest: [
            ModelArtifactTypedDigest: [(ModelArtifactTypedDigest, ModelEntry)]
        ],
        canonicalAliasByID: [String: String],
        localRecordCountByDigest: [ModelArtifactTypedDigest: Int]
    ) -> ModelEntry? {
        let digests = contentDigests(for: record)
        guard digests.allSatisfy({
            localRecordCountByDigest[$0] == 1
        }) else {
            return nil
        }
        let matches = digests.flatMap {
            trustedModelsByDigest[$0, default: []].map(\.1)
        }
        let uniqueMatches = InstalledModelsStore.uniqueByID(matches)
        if uniqueMatches.count == 1 {
            return uniqueMatches[0]
        }
        let canonicalIDs = Set(uniqueMatches.map {
            canonicalAliasByID[$0.id] ?? $0.id
        })
        guard canonicalIDs.count == 1,
              let canonicalID = canonicalIDs.first
        else {
            return nil
        }
        return uniqueMatches.first { $0.id == canonicalID }
    }

    private func contentDigests(
        for record: InstalledModelRecord
    ) -> [ModelArtifactTypedDigest] {
        record.identityHistory.customImport.map {
            [$0.contentDigest]
        } ?? record.model.artifactTypedDigests()
    }

    private func canonicalAliases(
        _ aliases: [ModelArtifactAlias]
    ) -> [String: String] {
        var result: [String: String] = [:]
        for alias in aliases {
            guard result[alias.aliasArtifactID] == nil else {
                return [:]
            }
            result[alias.aliasArtifactID] = alias.canonicalArtifactID
        }
        return result
    }

    private func canonicalLocalFiles(
        record: InstalledModelRecord,
        canonicalModel: ModelEntry
    ) -> [String: String] {
        if canonicalModel.files.count == 1,
           let localPath = record.localFilesByManifestFilename.values.first {
            return [canonicalModel.files[0].filename: localPath]
        }
        return Dictionary(
            uniqueKeysWithValues: canonicalModel.files.compactMap { file in
                record.localFilesByManifestFilename[file.filename].map {
                    (file.filename, $0)
                }
            }
        )
    }
}

public extension ModelEntry {
    func artifactTypedDigests() -> [ModelArtifactTypedDigest] {
        if runtime.artifactLayout == .singleFile, files.count == 1 {
            return [
                ModelArtifactTypedDigest(
                    type: .singleFileSHA256,
                    value: files[0].sha256
                ),
            ]
        }
        return [
            ModelArtifactTypedDigest(
                type: .artifactFingerprintSHA256,
                value: artifactFingerprint()
            ),
        ]
    }
}

extension ModelEntry {
    func copying(
        id: String? = nil,
        displayName: String? = nil
    ) -> ModelEntry {
        ModelEntry(
            id: id ?? self.id,
            displayName: displayName ?? self.displayName,
            tier: tier,
            description: description,
            sizeBytes: sizeBytes,
            files: files,
            licenses: licenses,
            provenance: provenance,
            runtimeParameters: runtimeParameters,
            hallucinationThresholds: hallucinationThresholds,
            minAppVersion: minAppVersion,
            runtime: runtime,
            capabilities: capabilities,
            presentation: presentation,
            purpose: purpose,
            installationStorage: installationStorage,
            benchmark: benchmark
        )
    }
}

private extension InstalledModelsStore {
    static func uniqueByID(_ models: [ModelEntry]) -> [ModelEntry] {
        var result: [ModelEntry] = []
        for model in models where !result.contains(where: { $0.id == model.id }) {
            result.append(model)
        }
        return result
    }
}
