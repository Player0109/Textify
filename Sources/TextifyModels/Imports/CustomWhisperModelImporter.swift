import CryptoKit
import Foundation

public struct CustomWhisperImportOptions: Equatable, Sendable {
    public let displayName: String
    public let licenseName: String

    public init(displayName: String, licenseName: String) {
        self.displayName = displayName
        self.licenseName = licenseName
    }
}

public enum CustomWhisperModelImportError: Error, Equatable, CustomStringConvertible {
    case sourceIsNotARegularFile
    case unsupportedFileHeader
    case invalidFileSize(Int64)
    case invalidDisplayName
    case invalidLicenseName
    case importedModelNotFound(String)

    public var description: String {
        switch self {
        case .sourceIsNotARegularFile:
            return "Choose a regular GGML or GGUF model file."
        case .unsupportedFileHeader:
            return "The selected file is not a recognized GGML or GGUF model."
        case let .invalidFileSize(size):
            return "The selected model has an unsupported size (\(size) bytes)."
        case .invalidDisplayName:
            return "Enter a name for the imported model."
        case .invalidLicenseName:
            return "Confirm the model license before importing."
        case let .importedModelNotFound(modelID):
            return "Imported model not found: \(modelID)."
        }
    }
}

public struct CustomWhisperModelImporter {
    public static let importedModelIDPrefix = "custom-sha256-"
    public static let minimumFileSizeBytes: Int64 = 1_048_576
    public static let maximumFileSizeBytes: Int64 = 8_589_934_592

    private let layout: ModelStorageLayout
    private let fileManager: FileManager
    private let trustedManifest: ModelManifest?
    private let nowISO8601: @Sendable () -> String

    public init(
        layout: ModelStorageLayout,
        fileManager: FileManager = .default,
        nowISO8601: @escaping @Sendable () -> String = {
            ISO8601DateFormatter().string(from: Date())
        }
    ) {
        self.init(
            layout: layout,
            trustedManifest: nil,
            fileManager: fileManager,
            nowISO8601: nowISO8601
        )
    }

    public init(
        layout: ModelStorageLayout,
        trustedManifest: ModelManifest?,
        fileManager: FileManager = .default,
        nowISO8601: @escaping @Sendable () -> String = {
            ISO8601DateFormatter().string(from: Date())
        }
    ) {
        self.layout = layout
        self.fileManager = fileManager
        self.trustedManifest = trustedManifest
        self.nowISO8601 = nowISO8601
    }

    public func importModel(
        from sourceURL: URL,
        options: CustomWhisperImportOptions
    ) async throws -> InstalledModelRecord {
        let displayName = options.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let licenseName = options.licenseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else {
            throw CustomWhisperModelImportError.invalidDisplayName
        }
        guard !licenseName.isEmpty else {
            throw CustomWhisperModelImportError.invalidLicenseName
        }

        let values = try sourceURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CustomWhisperModelImportError.sourceIsNotARegularFile
        }
        let sizeBytes = Int64(values.fileSize ?? -1)
        guard (Self.minimumFileSizeBytes...Self.maximumFileSizeBytes).contains(sizeBytes) else {
            throw CustomWhisperModelImportError.invalidFileSize(sizeBytes)
        }
        guard try Self.hasSupportedHeader(fileURL: sourceURL) else {
            throw CustomWhisperModelImportError.unsupportedFileHeader
        }

        let checksum = try Self.sha256Hex(fileURL: sourceURL)
        let digest = ModelArtifactTypedDigest(
            type: .singleFileSHA256,
            value: checksum
        )
        let modelID = Self.importedModelIDPrefix + checksum
        let existingStore = try loadStore()
        let matchingRecords = existingStore.records.filter {
            $0.identityHistory.customImport?.contentDigest == digest
                || $0.model.artifactTypedDigests().contains(digest)
        }
        if let existingRecord = matchingRecords.first(
            where: { $0.model.id == modelID }
        ) ?? matchingRecords.first {
            let updatedRecord = recordByAppendingImportHistory(
                to: existingRecord,
                digest: digest,
                displayName: displayName,
                sourceFilename: sourceURL.lastPathComponent
            )
            var prospectiveStore = existingStore
            _ = prospectiveStore.remove(modelID: existingRecord.model.id)
            prospectiveStore.upsert(updatedRecord)
            let reconciledStore = InstalledModelsStore(
                records: ModelArtifactPlacementResolver().reconcile(
                    records: prospectiveStore.records,
                    trustedManifest: trustedManifest
                ).records
            )
            guard let reconciledRecord = reconciledStore.records.first(
                where: { $0.storageModelID == existingRecord.storageModelID }
            ) else {
                throw CustomWhisperModelImportError.importedModelNotFound(
                    updatedRecord.model.id
                )
            }
            try JSONEncoder().encode(reconciledStore).write(
                to: layout.installedStoreURL,
                options: [.atomic]
            )
            return reconciledRecord
        }
        let installedFilename = "model.bin"
        let installedURL = try layout.installedFileURL(
            modelID: modelID,
            filename: installedFilename
        )
        let replacementURL = try layout.replacementFileURL(
            modelID: modelID,
            filename: installedFilename
        )
        try createDirectories()
        try fileManager.createDirectory(
            at: installedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if !fileManager.fileExists(atPath: installedURL.path)
            || (try? Self.sha256Hex(fileURL: installedURL)) != checksum {
            try? fileManager.removeItem(at: replacementURL)
            do {
                try fileManager.copyItem(at: sourceURL, to: replacementURL)
                if fileManager.fileExists(atPath: installedURL.path) {
                    _ = try fileManager.replaceItemAt(
                        installedURL,
                        withItemAt: replacementURL,
                        backupItemName: nil,
                        options: []
                    )
                } else {
                    try fileManager.moveItem(at: replacementURL, to: installedURL)
                }
            } catch {
                try? fileManager.removeItem(at: replacementURL)
                throw error
            }
        }

        let model = ModelEntry(
            id: modelID,
            displayName: displayName,
            tier: "custom",
            description: "User-imported Whisper-compatible local model.",
            sizeBytes: sizeBytes,
            files: [
                ModelFile(
                    filename: installedFilename,
                    url: "local-import://\(modelID)/\(installedFilename)",
                    sha256: checksum,
                    sizeBytes: sizeBytes
                )
            ],
            licenses: [
                ModelLicense(
                    scope: "model",
                    spdxId: "NOASSERTION",
                    name: licenseName,
                    licenseTextUrl: "about:blank"
                )
            ],
            provenance: ModelProvenance(
                sourceName: "User-selected local file",
                sourceUrl: "local-import://user-selected",
                sourceRevision: checksum,
                sourceFile: sourceURL.lastPathComponent,
                originalModelName: displayName,
                originalModelUrl: "local-import://user-selected",
                mirroredBy: "Textify user",
                mirroredAt: nowISO8601()
            ),
            runtimeParameters: RuntimeParameters(
                language: "en",
                detectLanguage: true,
                translate: false,
                strategy: "greedy",
                beamSize: 1,
                bestOf: 1,
                temperature: 0,
                temperatureFallback: [],
                noContext: true,
                tokenTimestamps: false,
                maxAudioSeconds: 60
            ),
            hallucinationThresholds: HallucinationThresholds(
                noSpeechProbabilityMax: 0.60,
                avgLogProbabilityMin: -1.00,
                compressionRatioMax: 2.40
            ),
            minAppVersion: "0.2.0",
            runtime: ModelRuntimeDescriptor(
                engine: .whisperCpp,
                variant: "whisper-custom-ggml",
                accelerator: .metalGPU,
                artifactLayout: .singleFile
            ),
            capabilities: ModelCapabilities(
                languages: ["*"],
                supportsTranslation: true,
                supportsCustomVocabulary: false
            ),
            presentation: ModelUserPresentation(
                expectedFinalization: "Depends on the imported checkpoint",
                accuracyTradeoff: "Quality and speed are determined by the model you supplied.",
                requirements: "Apple Silicon and a Whisper-compatible GGML or GGUF file"
            ),
            installationStorage: ModelInstallationStorage(
                finalArtifactBytes: sizeBytes,
                peakInstallationBytes: sizeBytes
            )
        )
        let record = InstalledModelRecord(
            model: model,
            installedAt: nowISO8601(),
            localFilesByManifestFilename: [installedFilename: installedURL.path],
            storageModelID: modelID,
            identityHistory: InstalledModelIdentityHistory(
                customImport: CustomModelImportHistory(
                    contentDigest: digest,
                    localNames: [displayName],
                    sourceFilenames: [sourceURL.lastPathComponent]
                )
            )
        )
        let canonicalRecord = ModelArtifactPlacementResolver()
            .reconcile(records: [record], trustedManifest: trustedManifest)
            .records[0]
        try upsertInstalledRecord(canonicalRecord)
        return canonicalRecord
    }

    public func removeImportedModel(modelID: String) throws {
        var store = try loadStore()
        guard modelID.hasPrefix(Self.importedModelIDPrefix),
              store.record(forModelID: modelID) != nil
        else {
            throw CustomWhisperModelImportError.importedModelNotFound(modelID)
        }
        _ = store.remove(modelID: modelID)
        try JSONEncoder().encode(store).write(to: layout.installedStoreURL, options: [.atomic])
        let directory = try layout.installedModelDirectory(modelID: modelID)
        try? fileManager.removeItem(at: directory)
    }

    private func createDirectories() throws {
        for directory in [
            layout.rootDirectory,
            layout.downloadsDirectory,
            layout.installedModelsDirectory
        ] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
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

    private func upsertInstalledRecord(_ record: InstalledModelRecord) throws {
        var store = try loadStore()
        store.upsert(record)
        try JSONEncoder().encode(store).write(to: layout.installedStoreURL, options: [.atomic])
    }

    private static func hasSupportedHeader(fileURL: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        guard let header = try handle.read(upToCount: 4), header.count == 4 else {
            return false
        }
        return [
            Data([0x6c, 0x6d, 0x67, 0x67]), // ggml
            Data([0x66, 0x6d, 0x67, 0x67]), // ggmf
            Data([0x74, 0x6a, 0x67, 0x67]), // ggjt
            Data("GGUF".utf8)
        ].contains(header)
    }

    private static func sha256Hex(fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func appendingUnique(_ value: String, to values: [String]) -> [String] {
        values.contains(value) ? values : values + [value]
    }

    private func recordByAppendingImportHistory(
        to record: InstalledModelRecord,
        digest: ModelArtifactTypedDigest,
        displayName: String,
        sourceFilename: String
    ) -> InstalledModelRecord {
        let priorHistory = record.identityHistory.customImport
        let isCurrentCuratedIdentity = trustedManifest?.models.contains {
            $0.id == record.model.id
        } == true
        let model = isCurrentCuratedIdentity
            ? record.model
            : record.model.copying(
                id: Self.importedModelIDPrefix + digest.value,
                displayName: displayName
            )
        let priorLocalNames = priorHistory?.localNames
            ?? (isCurrentCuratedIdentity ? [] : [record.model.displayName])
        let priorSourceFilenames = priorHistory?.sourceFilenames
            ?? (isCurrentCuratedIdentity ? [] : [record.model.provenance.sourceFile])
        return InstalledModelRecord(
            model: model,
            installedAt: record.installedAt,
            localFilesByManifestFilename: record.localFilesByManifestFilename,
            storageModelID: record.storageModelID,
            identityHistory: InstalledModelIdentityHistory(
                wasCurated: record.identityHistory.wasCurated,
                customImport: CustomModelImportHistory(
                    contentDigest: digest,
                    localNames: Self.appendingUnique(
                        displayName,
                        to: priorLocalNames
                    ),
                    sourceFilenames: Self.appendingUnique(
                        sourceFilename,
                        to: priorSourceFilenames
                    )
                )
            ),
            verifiedRestorationIDs: record.verifiedRestorationIDs
        )
    }
}
