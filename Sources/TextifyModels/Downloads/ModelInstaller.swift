import CryptoKit
import Darwin
import Foundation

public protocol InstalledModelFileReplacing {
    func replaceExistingInstalledFile(at installedURL: URL, with replacementURL: URL) throws
}

public struct FileManagerInstalledModelFileReplacer: InstalledModelFileReplacing {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func replaceExistingInstalledFile(at installedURL: URL, with replacementURL: URL) throws {
        _ = try fileManager.replaceItemAt(
            installedURL,
            withItemAt: replacementURL,
            backupItemName: nil,
            options: []
        )
    }
}

private final class ModelCapacityRecheckGate: @unchecked Sendable {
    private let intervalBytes: Int64
    private let lock = NSLock()
    private var lastCheckedBytes: Int64 = 0

    init(intervalBytes: Int64) {
        self.intervalBytes = max(1, intervalBytes)
    }

    func shouldCheck(progress: DownloadFileProgress) -> Bool {
        lock.withLock {
            let advanced = progress.bytesDownloaded - lastCheckedBytes
            guard advanced >= intervalBytes
                    || (
                        progress.totalBytes > 0
                            && progress.bytesDownloaded
                                >= progress.totalBytes
                    )
            else {
                return false
            }
            lastCheckedBytes = progress.bytesDownloaded
            return true
        }
    }
}

public struct ModelInstaller {
    private let layout: ModelStorageLayout
    private let transport: any DownloadTransport
    private let fileManager: FileManager
    private let fileReplacer: any InstalledModelFileReplacing
    private let currentAppVersion: String
    private let nowISO8601: @Sendable () -> String
    private let capacityRecheckIntervalBytes: Int64
    private let availableCapacity: @Sendable (URL) throws -> Int64

    public init(
        layout: ModelStorageLayout,
        transport: any DownloadTransport,
        fileManager: FileManager = .default,
        fileReplacer: (any InstalledModelFileReplacing)? = nil,
        currentAppVersion: String = "1.1.0",
        nowISO8601: @escaping @Sendable () -> String = { ISO8601DateFormatter().string(from: Date()) },
        capacityRecheckIntervalBytes: Int64 = 64_000_000,
        availableCapacity: @escaping @Sendable (URL) throws -> Int64 = { url in
            try ModelVolumeCapacityProvider().availableCapacity(at: url)
        }
    ) {
        self.layout = layout
        self.transport = transport
        self.fileManager = fileManager
        self.fileReplacer = fileReplacer ?? FileManagerInstalledModelFileReplacer(fileManager: fileManager)
        self.currentAppVersion = currentAppVersion
        self.nowISO8601 = nowISO8601
        self.capacityRecheckIntervalBytes = max(
            1,
            capacityRecheckIntervalBytes
        )
        self.availableCapacity = availableCapacity
    }

    public func install(
        modelID: String,
        from manifest: ModelManifest,
        onStateChange: @escaping @Sendable (DownloadState) -> Void = { _ in }
    ) async throws -> InstalledModelRecord {
        do {
            return try await installReportingFailures(
                modelID: modelID,
                from: manifest,
                onStateChange: onStateChange
            )
        } catch {
            let reportedError = storageAdjustedError(
                error,
                modelID: modelID,
                manifest: manifest
            )
            onStateChange(DownloadState(
                modelID: modelID,
                phase: .failed,
                message: String(describing: reportedError)
            ))
            throw reportedError
        }
    }

    private func installReportingFailures(
        modelID: String,
        from manifest: ModelManifest,
        onStateChange: @escaping @Sendable (DownloadState) -> Void
    ) async throws -> InstalledModelRecord {
        try ProductionModelPolicy.validateProductionManifest(manifest)

        guard let model = manifest.models.first(where: { $0.id == modelID }) else {
            throw ModelInstallError.modelNotFound(modelID)
        }
        guard ProductionModelPolicy.appVersion(
            currentAppVersion,
            satisfiesMinimum: model.minAppVersion
        ) else {
            throw ModelInstallError.minimumAppVersionRequired(
                modelID: model.id,
                required: model.minAppVersion,
                current: currentAppVersion
            )
        }
        if model.runtime.artifactLayout == .modelDirectory {
            return try await installDirectoryModel(
                model,
                onStateChange: onStateChange
            )
        }
        guard model.files.count == 1 else {
            throw ModelInstallError.expectedSingleFile(count: model.files.count)
        }
        let file = model.files[0]
        guard let url = URL(string: file.url) else {
            throw ModelInstallError.invalidDownloadURL(file.url)
        }
        try ModelDownloadURLPolicy.requireApprovedModelFile(url)

        try createDirectories()
        let installedModelDirectory = try layout.installedModelDirectory(modelID: model.id)
        let temporaryURL = try layout.temporaryDownloadURL(modelID: model.id, filename: file.filename)
        let installedURL = try layout.installedFileURL(modelID: model.id, filename: file.filename)
        let replacementURL = try layout.replacementFileURL(modelID: model.id, filename: file.filename)

        if let existingRecord = existingValidInstalledRecord(
            model: model,
            file: file,
            installedURL: installedURL
        ) {
            let refreshedRecord = InstalledModelRecord(
                model: model,
                installedAt: existingRecord.installedAt,
                localFilesByManifestFilename: existingRecord.localFilesByManifestFilename
            )
            if refreshedRecord != existingRecord {
                try upsertInstalledRecord(refreshedRecord)
            }
            onStateChange(DownloadState(
                modelID: model.id,
                phase: .installed,
                bytesDownloaded: file.sizeBytes,
                totalBytes: file.sizeBytes,
                message: "Model already installed and verified."
            ))
            return refreshedRecord
        }

        try? fileManager.removeItem(at: replacementURL)

        onStateChange(DownloadState(
            modelID: model.id,
            phase: .checkingSpace,
            totalBytes: file.sizeBytes,
            message: "Preparing model download."
        ))
        try requireCapacity(for: model)
        onStateChange(DownloadState(
            modelID: model.id,
            phase: .downloading,
            totalBytes: file.sizeBytes,
            message: "Downloading model."
        ))
        let recheckGate = ModelCapacityRecheckGate(
            intervalBytes: capacityRecheckIntervalBytes
        )
        _ = try await downloadFile(
            file,
            modelID: model.id,
            from: url,
            to: temporaryURL,
            admissionCheck: { progress in
                guard recheckGate.shouldCheck(progress: progress) else {
                    return
                }
                try requireCapacity(
                    for: model,
                    additionalValidatedFiles: [
                        (
                            url: temporaryURL,
                            logicalBytes: min(
                                file.sizeBytes,
                                progress.bytesDownloaded
                            )
                        ),
                    ]
                )
            },
            progress: { progress in
            onStateChange(DownloadState(
                modelID: model.id,
                phase: .downloading,
                bytesDownloaded: progress.bytesDownloaded,
                totalBytes: progress.totalBytes > 0 ? progress.totalBytes : file.sizeBytes,
                message: "Downloading model."
            ))
        })
        let downloadedSize = fileSize(at: temporaryURL) ?? -1
        guard downloadedSize == file.sizeBytes else {
            removeDownloadState(modelID: model.id, file: file, temporaryURL: temporaryURL)
            throw ModelInstallError.unexpectedDownloadSize(
                expectedBytes: file.sizeBytes,
                actualBytes: downloadedSize
            )
        }
        onStateChange(DownloadState(
            modelID: model.id,
            phase: .verifying,
            bytesDownloaded: file.sizeBytes,
            totalBytes: file.sizeBytes,
            message: "Verifying model."
        ))
        let actualChecksum = try sha256Hex(fileURL: temporaryURL)
        guard actualChecksum.lowercased() == file.sha256.lowercased() else {
            removeDownloadState(modelID: model.id, file: file, temporaryURL: temporaryURL)
            throw ModelInstallError.checksumMismatch(expected: file.sha256, actual: actualChecksum)
        }

        try Task.checkCancellation()
        try requireCapacity(
            for: model,
            additionalValidatedFiles: [
                (url: temporaryURL, logicalBytes: file.sizeBytes),
            ]
        )
        onStateChange(DownloadState(
            modelID: model.id,
            phase: .installing,
            bytesDownloaded: file.sizeBytes,
            totalBytes: file.sizeBytes,
            message: "Installing model."
        ))
        try fileManager.createDirectory(
            at: installedModelDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: temporaryURL, to: replacementURL)
        do {
            try replaceInstalledFile(
                replacementURL: replacementURL,
                installedURL: installedURL
            )
        } catch {
            try? fileManager.removeItem(at: replacementURL)
            throw error
        }

        let record = InstalledModelRecord(
            model: model,
            installedAt: nowISO8601(),
            localFilesByManifestFilename: [file.filename: installedURL.path]
        )
        try upsertInstalledRecord(record)
        onStateChange(DownloadState(
            modelID: model.id,
            phase: .installed,
            bytesDownloaded: file.sizeBytes,
            totalBytes: file.sizeBytes,
            message: "Model installed and verified."
        ))
        return record
    }

    private func installDirectoryModel(
        _ model: ModelEntry,
        onStateChange: @escaping @Sendable (DownloadState) -> Void
    ) async throws -> InstalledModelRecord {
        let downloads = try model.files.map { file -> (ModelFile, URL) in
            guard let url = URL(string: file.url) else {
                throw ModelInstallError.invalidDownloadURL(file.url)
            }
            try ModelDownloadURLPolicy.requireApprovedModelFile(url)
            guard file.relativePath != nil else {
                throw ProductionModelPolicyError.missingRelativePath(
                    modelID: model.id,
                    filename: file.filename
                )
            }
            return (file, url)
        }

        try createDirectories()
        let installedDirectory = try layout.installedModelDirectory(modelID: model.id)
        if let existingRecord = existingValidInstalledDirectoryRecord(
            model: model,
            installedDirectory: installedDirectory
        ) {
            let refreshedRecord = InstalledModelRecord(
                model: model,
                installedAt: existingRecord.installedAt,
                localFilesByManifestFilename: existingRecord.localFilesByManifestFilename
            )
            if refreshedRecord != existingRecord {
                try upsertInstalledRecord(refreshedRecord)
            }
            onStateChange(DownloadState(
                modelID: model.id,
                phase: .installed,
                bytesDownloaded: model.sizeBytes,
                totalBytes: model.sizeBytes,
                message: "Model already installed and verified."
            ))
            return refreshedRecord
        }

        let stagingDirectory = try layout.temporaryInstallationDirectory(modelID: model.id)
        try? fileManager.removeItem(at: stagingDirectory)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: stagingDirectory)
        }

        onStateChange(DownloadState(
            modelID: model.id,
            phase: .checkingSpace,
            totalBytes: model.sizeBytes,
            message: "Preparing model download."
        ))
        try requireCapacity(for: model)

        var completedBytes: Int64 = 0
        var installedPaths: [String: String] = [:]
        var validatedStagingFiles: [(url: URL, logicalBytes: Int64)] = []
        for (file, url) in downloads {
            try Task.checkCancellation()
            let temporaryURL = try layout.temporaryDownloadURL(
                modelID: model.id,
                filename: file.filename
            )
            onStateChange(DownloadState(
                modelID: model.id,
                phase: .downloading,
                bytesDownloaded: completedBytes,
                totalBytes: model.sizeBytes,
                message: "Downloading model files."
            ))
            let completedBytesBeforeFile = completedBytes
            let recheckGate = ModelCapacityRecheckGate(
                intervalBytes: capacityRecheckIntervalBytes
            )
            let validatedFilesBeforeDownload = validatedStagingFiles
            _ = try await downloadFile(
                file,
                modelID: model.id,
                from: url,
                to: temporaryURL,
                admissionCheck: { progress in
                    guard recheckGate.shouldCheck(progress: progress) else {
                        return
                    }
                    try requireCapacity(
                        for: model,
                        additionalValidatedFiles:
                            validatedFilesBeforeDownload + [
                                (
                                    url: temporaryURL,
                                    logicalBytes: min(
                                        file.sizeBytes,
                                        progress.bytesDownloaded
                                    )
                                ),
                            ]
                    )
                },
                progress: { progress in
                onStateChange(DownloadState(
                    modelID: model.id,
                    phase: .downloading,
                    bytesDownloaded: min(
                        model.sizeBytes,
                        completedBytesBeforeFile + max(0, progress.bytesDownloaded)
                    ),
                    totalBytes: model.sizeBytes,
                    message: "Downloading model files."
                ))
            })

            let downloadedSize = fileSize(at: temporaryURL) ?? -1
            guard downloadedSize == file.sizeBytes else {
                removeDownloadState(modelID: model.id, file: file, temporaryURL: temporaryURL)
                throw ModelInstallError.unexpectedDownloadSize(
                    expectedBytes: file.sizeBytes,
                    actualBytes: downloadedSize
                )
            }
            onStateChange(DownloadState(
                modelID: model.id,
                phase: .verifying,
                bytesDownloaded: completedBytes + file.sizeBytes,
                totalBytes: model.sizeBytes,
                message: "Verifying model files."
            ))
            let actualChecksum = try sha256Hex(fileURL: temporaryURL)
            guard actualChecksum.lowercased() == file.sha256.lowercased() else {
                removeDownloadState(modelID: model.id, file: file, temporaryURL: temporaryURL)
                throw ModelInstallError.checksumMismatch(
                    expected: file.sha256,
                    actual: actualChecksum
                )
            }
            try requireCapacity(
                for: model,
                additionalValidatedFiles:
                    validatedFilesBeforeDownload + [
                        (
                            url: temporaryURL,
                            logicalBytes: file.sizeBytes
                        ),
                    ]
            )

            let relativePath = file.relativePath ?? file.filename
            let stagingURL = try layout.artifactURL(
                in: stagingDirectory,
                relativePath: relativePath
            )
            try fileManager.createDirectory(
                at: stagingURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: temporaryURL, to: stagingURL)
            validatedStagingFiles.append(
                (url: stagingURL, logicalBytes: file.sizeBytes)
            )
            installedPaths[file.filename] = try layout.installedArtifactURL(
                modelID: model.id,
                relativePath: relativePath
            ).path
            completedBytes += file.sizeBytes
        }

        try Task.checkCancellation()
        try requireCapacity(
            for: model,
            additionalValidatedFiles: validatedStagingFiles
        )
        onStateChange(DownloadState(
            modelID: model.id,
            phase: .installing,
            bytesDownloaded: model.sizeBytes,
            totalBytes: model.sizeBytes,
            message: "Installing model."
        ))
        if fileManager.fileExists(atPath: installedDirectory.path) {
            try fileReplacer.replaceExistingInstalledFile(
                at: installedDirectory,
                with: stagingDirectory
            )
        } else {
            try fileManager.moveItem(at: stagingDirectory, to: installedDirectory)
        }

        let record = InstalledModelRecord(
            model: model,
            installedAt: nowISO8601(),
            localFilesByManifestFilename: installedPaths
        )
        try upsertInstalledRecord(record)
        onStateChange(DownloadState(
            modelID: model.id,
            phase: .installed,
            bytesDownloaded: model.sizeBytes,
            totalBytes: model.sizeBytes,
            message: "Model installed and verified."
        ))
        return record
    }

    private func createDirectories() throws {
        for directory in [
            layout.rootDirectory,
            layout.manifestsDirectory,
            layout.downloadsDirectory,
            layout.installedModelsDirectory
        ] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func downloadFile(
        _ file: ModelFile,
        modelID: String,
        from url: URL,
        to temporaryURL: URL,
        admissionCheck: @escaping @Sendable (
            DownloadFileProgress
        ) throws -> Void,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse {
        let metadataURL = try layout.downloadResumeMetadataURL(
            modelID: modelID,
            filename: file.filename
        )
        if let resumableTransport = transport as? any ResumableDownloadTransport {
            return try await resumableTransport.downloadFileResuming(
                URLRequest(url: url),
                to: temporaryURL,
                metadataURL: metadataURL,
                modelID: modelID,
                expectedSHA256: file.sha256,
                maximumBytes: file.sizeBytes,
                admissionCheck: admissionCheck,
                progress: progress
            )
        }

        try? fileManager.removeItem(at: temporaryURL)
        try? fileManager.removeItem(at: metadataURL)
        return try await transport.downloadFile(
            URLRequest(url: url),
            to: temporaryURL,
            maximumBytes: file.sizeBytes,
            admissionCheck: admissionCheck,
            progress: progress
        )
    }

    private func requireCapacity(
        for model: ModelEntry,
        additionalValidatedFiles: [(url: URL, logicalBytes: Int64)] = []
    ) throws {
        guard let storage = model.installationStorage else {
            throw ProductionModelPolicyError.missingInstallationStorage(
                modelID: model.id
            )
        }
        let reusable: ModelReusableStorage
        do {
            reusable = try ModelReusableStorageInspector.inspect(
                layout: layout,
                modelID: model.id,
                expectedFiles: model.files,
                additionalValidatedFiles: additionalValidatedFiles,
                fileManager: fileManager
            ).storage
        } catch {
            throw ModelInstallError.storageCapacityUnavailable
        }
        let requirement = ModelStorageAdmissionRequirement(
            completeTransferBytes: model.sizeBytes,
            finalArtifactBytes: storage.finalArtifactBytes,
            peakInstallationBytes: storage.peakInstallationBytes
        )
        let currentCapacity: Int64
        do {
            currentCapacity = try availableCapacity(layout.rootDirectory)
        } catch {
            throw ModelInstallError.storageCapacityUnavailable
        }
        try requirement.requireCapacity(
            availableBytes: currentCapacity,
            reusable: reusable
        )
    }

    private func storageAdjustedError(
        _ error: any Error,
        modelID: String,
        manifest: ModelManifest
    ) -> any Error {
        guard Self.isOutOfSpace(error),
              let model = manifest.models.first(
                where: { $0.id == modelID }
              )
        else {
            return error
        }
        do {
            try requireCapacity(for: model)
            return ModelInstallError.filesystem(
                "The model volume ran out of space. Free storage and try again."
            )
        } catch {
            return error
        }
    }

    private static func isOutOfSpace(_ error: any Error) -> Bool {
        let nsError = error as NSError
        return (
            nsError.domain == NSPOSIXErrorDomain
                && nsError.code == Int(ENOSPC)
        ) || (
            nsError.domain == NSCocoaErrorDomain
                && nsError.code
                    == CocoaError.fileWriteOutOfSpace.rawValue
        )
    }

    private func removeDownloadState(
        modelID: String,
        file: ModelFile,
        temporaryURL: URL
    ) {
        try? fileManager.removeItem(at: temporaryURL)
        if let metadataURL = try? layout.downloadResumeMetadataURL(
            modelID: modelID,
            filename: file.filename
        ) {
            try? fileManager.removeItem(at: metadataURL)
        }
    }

    private func upsertInstalledRecord(_ record: InstalledModelRecord) throws {
        var store = try loadStore()
        store.upsert(record)
        let data = try JSONEncoder().encode(store)
        try data.write(to: layout.installedStoreURL, options: [.atomic])
    }

    private func replaceInstalledFile(
        replacementURL: URL,
        installedURL: URL
    ) throws {
        guard fileManager.fileExists(atPath: installedURL.path) else {
            try fileManager.moveItem(at: replacementURL, to: installedURL)
            return
        }

        try fileReplacer.replaceExistingInstalledFile(at: installedURL, with: replacementURL)
    }

    private func loadStore() throws -> InstalledModelsStore {
        guard fileManager.fileExists(atPath: layout.installedStoreURL.path) else {
            return InstalledModelsStore()
        }
        let data = try Data(contentsOf: layout.installedStoreURL)
        return try JSONDecoder().decode(InstalledModelsStore.self, from: data)
    }

    private func existingValidInstalledRecord(
        model: ModelEntry,
        file: ModelFile,
        installedURL: URL
    ) -> InstalledModelRecord? {
        guard let record = try? loadStore().record(forModelID: model.id),
              record.localFilesByManifestFilename[file.filename] == installedURL.path,
              fileManager.fileExists(atPath: installedURL.path),
              fileSize(at: installedURL) == file.sizeBytes,
              (try? sha256Hex(fileURL: installedURL)) == file.sha256.lowercased()
        else {
            return nil
        }

        return record
    }

    private func existingValidInstalledDirectoryRecord(
        model: ModelEntry,
        installedDirectory: URL
    ) -> InstalledModelRecord? {
        guard let record = try? loadStore().record(forModelID: model.id),
              fileManager.fileExists(atPath: installedDirectory.path)
        else {
            return nil
        }

        for file in model.files {
            guard let relativePath = file.relativePath,
                  let installedURL = try? layout.installedArtifactURL(
                      modelID: model.id,
                      relativePath: relativePath
                  ),
                  record.localFilesByManifestFilename[file.filename] == installedURL.path,
                  fileManager.fileExists(atPath: installedURL.path),
                  fileSize(at: installedURL) == file.sizeBytes,
                  (try? sha256Hex(fileURL: installedURL)) == file.sha256.lowercased()
            else {
                return nil
            }
        }
        return record
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let fileSize = try? fileManager
            .attributesOfItem(atPath: url.path)[.size] as? NSNumber
        else {
            return nil
        }
        return fileSize.int64Value
    }

    private func sha256Hex(fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
