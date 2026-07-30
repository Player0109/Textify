import CryptoKit
import Foundation
import TextifyModels
import TextifySettings

public actor RuntimeModelResolverAdapter: RuntimeModelResolving {
    private let layout: ModelStorageLayout
    private let loadStore: @Sendable () throws -> InstalledModelsStore
    private let hashFile: @Sendable (URL) throws -> String
    private var verifiedFilesByPath: [String: VerifiedFileFingerprint] = [:]

    public init(
        layout: ModelStorageLayout,
        loadStore: @escaping @Sendable () throws -> InstalledModelsStore
    ) {
        self.init(
            layout: layout,
            loadStore: loadStore,
            hashFile: { try RuntimeModelResolverAdapter.sha256Hex(fileURL: $0) }
        )
    }

    init(
        layout: ModelStorageLayout,
        loadStore: @escaping @Sendable () throws -> InstalledModelsStore,
        hashFile: @escaping @Sendable (URL) throws -> String
    ) {
        self.layout = layout
        self.loadStore = loadStore
        self.hashFile = hashFile
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
              record.model.purpose == .transcription,
              let installedFiles = installedFiles(for: record),
              let firstInstalledFile = installedFiles.first
        else {
            return nil
        }

        let localModelURL: URL
        switch record.model.runtime.artifactLayout {
        case .singleFile:
            localModelURL = firstInstalledFile.url
        case .modelDirectory:
            guard let installedDirectory = try? layout.installedModelDirectory(
                modelID: record.storageModelID
            ) else {
                return nil
            }
            localModelURL = installedDirectory
        }

        let selectedLanguage = preferences.transcriptionLanguage.rawValue
        let supportedLanguages = record.model.capabilities.languages
        let supportsSelectedLanguage = supportedLanguages.contains(selectedLanguage)
            || supportedLanguages.contains("*")
        guard selectedLanguage == "auto" || supportsSelectedLanguage else {
            return nil
        }

        let baseParameters = record.model.runtimeParameters
        let supportsAutomaticLanguage = baseParameters.detectLanguage
            || supportedLanguages.contains("*")
            || supportedLanguages.count > 1
        let detectLanguage = selectedLanguage == "auto" && supportsAutomaticLanguage
        let language = selectedLanguage == "auto"
            ? detectLanguage ? "auto" : baseParameters.language
            : selectedLanguage
        let runtimeParameters = RuntimeParameters(
            language: language,
            detectLanguage: detectLanguage,
            translate: baseParameters.translate,
            strategy: baseParameters.strategy,
            beamSize: baseParameters.beamSize,
            bestOf: baseParameters.bestOf,
            temperature: baseParameters.temperature,
            temperatureFallback: baseParameters.temperatureFallback,
            noContext: baseParameters.noContext,
            tokenTimestamps: baseParameters.tokenTimestamps,
            maxAudioSeconds: baseParameters.maxAudioSeconds
        )

        return RuntimeActiveModel(
            id: record.model.id,
            displayName: record.model.displayName,
            tier: record.model.tier,
            localModelPath: localModelURL.path,
            useGPU: record.model.runtime.accelerator == .metalGPU,
            threadCount: ProcessInfo.processInfo.activeProcessorCount,
            engine: record.model.runtime.engine,
            variant: record.model.runtime.variant,
            accelerator: record.model.runtime.accelerator,
            artifactLayout: record.model.runtime.artifactLayout,
            runtimeParameters: runtimeParameters,
            purpose: record.model.purpose
        )
    }

    public func resolveActiveVoiceCleaningModel(preferences: AppPreferences) async -> RuntimeActiveModel? {
        guard let modelID = preferences.activeVoiceCleaningModelID,
              let record = try? loadStore().record(forModelID: modelID),
              record.model.purpose == .voiceCleaning,
              let installedFiles = installedFiles(for: record),
              !installedFiles.isEmpty,
              let installedDirectory = try? layout.installedModelDirectory(
                  modelID: record.storageModelID
              )
        else {
            return nil
        }

        return RuntimeActiveModel(
            id: record.model.id,
            displayName: record.model.displayName,
            tier: record.model.tier,
            localModelPath: installedDirectory.path,
            useGPU: true,
            threadCount: nil,
            engine: record.model.runtime.engine,
            variant: record.model.runtime.variant,
            accelerator: record.model.runtime.accelerator,
            artifactLayout: record.model.runtime.artifactLayout,
            runtimeParameters: record.model.runtimeParameters,
            purpose: record.model.purpose
        )
    }

    public func readiness(for model: RuntimeActiveModel?) async -> RuntimeModelReadiness {
        guard let model else {
            return .noActiveModel
        }

        guard let record = try? loadStore().record(forModelID: model.id),
              let installedFiles = installedFiles(for: record),
              let firstInstalledFile = installedFiles.first
        else {
            verifiedFilesByPath.removeAll()
            return .missing(modelID: model.id)
        }
        let expectedRuntimePath: String
        switch model.artifactLayout {
        case .singleFile:
            expectedRuntimePath = firstInstalledFile.url.path
        case .modelDirectory:
            guard let installedDirectory = try? layout.installedModelDirectory(
                modelID: record.storageModelID
            ) else {
                verifiedFilesByPath.removeAll()
                return .failed(modelID: model.id, reason: .checksumFailed)
            }
            expectedRuntimePath = installedDirectory.path
        }
        guard expectedRuntimePath == model.localModelPath else {
            verifiedFilesByPath.removeAll()
            return .failed(modelID: model.id, reason: .checksumFailed)
        }

        for installedFile in installedFiles {
            guard FileManager.default.fileExists(atPath: installedFile.url.path) else {
                verifiedFilesByPath[installedFile.url.path] = nil
                return .missing(modelID: model.id)
            }
            guard let attributes = fileAttributes(at: installedFile.url),
                  attributes.size == installedFile.manifestFile.sizeBytes
            else {
                verifiedFilesByPath[installedFile.url.path] = nil
                return .failed(modelID: model.id, reason: .checksumFailed)
            }
            let fingerprint = VerifiedFileFingerprint(
                path: installedFile.url.path,
                expectedSHA256: installedFile.manifestFile.sha256,
                size: attributes.size,
                modificationDate: attributes.modificationDate
            )
            if verifiedFilesByPath[installedFile.url.path] == fingerprint {
                continue
            }
            guard (try? hashFile(installedFile.url)) == installedFile.manifestFile.sha256 else {
                verifiedFilesByPath[installedFile.url.path] = nil
                return .failed(modelID: model.id, reason: .checksumFailed)
            }
            verifiedFilesByPath[installedFile.url.path] = fingerprint
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

    private func installedFiles(for record: InstalledModelRecord) -> [InstalledFile]? {
        guard let storageDirectory = try? layout.installedModelDirectory(
            modelID: record.storageModelID
        ) else {
            return nil
        }
        let storagePath = storageDirectory.resolvingSymlinksInPath()
            .standardizedFileURL.path + "/"
        let installedFiles = record.model.files.compactMap { manifestFile -> InstalledFile? in
            guard let receiptPath = record.localFilesByManifestFilename[
                manifestFile.filename
            ]
            else {
                return nil
            }
            let receiptURL = URL(fileURLWithPath: receiptPath)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            guard receiptURL.path.hasPrefix(storagePath) else {
                return nil
            }
            return InstalledFile(url: receiptURL, manifestFile: manifestFile)
        }
        guard installedFiles.count == record.model.files.count else {
            return nil
        }
        return installedFiles
    }

    private func fileAttributes(at url: URL) -> (size: Int64, modificationDate: Date)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber,
              let modificationDate = attributes[.modificationDate] as? Date
        else {
            return nil
        }
        return (fileSize.int64Value, modificationDate)
    }

    private static func sha256Hex(fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private struct InstalledFile {
        let url: URL
        let manifestFile: ModelFile
    }

    private struct VerifiedFileFingerprint: Equatable {
        let path: String
        let expectedSHA256: String
        let size: Int64
        let modificationDate: Date
    }
}
