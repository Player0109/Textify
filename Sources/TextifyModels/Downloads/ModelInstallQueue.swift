import Foundation

public enum ModelInstallQueueAction: String, Codable, Equatable, Sendable {
    case install
    case reinstall
}

public struct ModelInstallArtifactIdentity:
    Codable,
    Equatable,
    Sendable
{
    public let artifactID: String
    public let contentDigests: [ModelRevocationDigestTarget]
    public let expectedFiles: [ModelFile]

    public init(
        artifactID: String,
        contentDigests: [ModelRevocationDigestTarget],
        expectedFiles: [ModelFile] = []
    ) {
        self.artifactID = artifactID
        self.contentDigests = contentDigests
        self.expectedFiles = expectedFiles
    }

    public init(model: ModelEntry) {
        artifactID = model.id
        expectedFiles = model.files
        var digests = [
            ModelRevocationDigestTarget(
                algorithm: .sha256,
                value: model.artifactFingerprint(),
                scope: .canonicalLayout(version: 1)
            ),
        ]
        if model.runtime.artifactLayout == .singleFile,
           model.files.count == 1,
           let file = model.files.first {
            digests.append(
                ModelRevocationDigestTarget(
                    algorithm: .sha256,
                    value: file.sha256,
                    scope: .singleFilePayload
                )
            )
        }
        digests.append(
            contentsOf: model.files.map {
                ModelRevocationDigestTarget(
                    algorithm: .sha256,
                    value: $0.sha256,
                    scope: .managedFile(
                        relativePath: $0.relativePath ?? $0.filename
                    )
                )
            }
        )
        contentDigests = digests
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        artifactID = try container.decode(
            String.self,
            forKey: .artifactID
        )
        contentDigests = try container.decode(
            [ModelRevocationDigestTarget].self,
            forKey: .contentDigests
        )
        expectedFiles = try container.decodeIfPresent(
            [ModelFile].self,
            forKey: .expectedFiles
        ) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case artifactID
        case contentDigests
        case expectedFiles
    }
}

public struct ModelInstallResumableData: Codable, Equatable, Sendable {
    public let sourceAttemptID: String
    public let associatedAttemptID: String
    public let validatedBytes: Int64
    public let fileCount: Int
    public let filenames: [String]

    public init(
        sourceAttemptID: String,
        associatedAttemptID: String,
        validatedBytes: Int64,
        fileCount: Int
    ) {
        self.init(
            sourceAttemptID: sourceAttemptID,
            associatedAttemptID: associatedAttemptID,
            validatedBytes: validatedBytes,
            fileCount: fileCount,
            filenames: []
        )
    }

    public init(
        sourceAttemptID: String,
        associatedAttemptID: String,
        validatedBytes: Int64,
        fileCount: Int,
        filenames: [String]
    ) {
        self.sourceAttemptID = sourceAttemptID
        self.associatedAttemptID = associatedAttemptID
        self.validatedBytes = max(0, validatedBytes)
        self.fileCount = max(0, fileCount)
        self.filenames = Array(Set(filenames)).sorted()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceAttemptID = try container.decode(
            String.self,
            forKey: .sourceAttemptID
        )
        associatedAttemptID = try container.decode(
            String.self,
            forKey: .associatedAttemptID
        )
        validatedBytes = max(
            0,
            try container.decode(Int64.self, forKey: .validatedBytes)
        )
        fileCount = max(
            0,
            try container.decode(Int.self, forKey: .fileCount)
        )
        filenames = try container.decodeIfPresent(
            [String].self,
            forKey: .filenames
        ) ?? []
    }

    func reassociated(
        from sourceAttemptID: String,
        to attemptID: String
    ) -> ModelInstallResumableData {
        ModelInstallResumableData(
            sourceAttemptID: sourceAttemptID,
            associatedAttemptID: attemptID,
            validatedBytes: validatedBytes,
            fileCount: fileCount,
            filenames: filenames
        )
    }

    private enum CodingKeys: String, CodingKey {
        case sourceAttemptID
        case associatedAttemptID
        case validatedBytes
        case fileCount
        case filenames
    }
}

public struct ModelInstallQueueAttempt: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let artifactID: String
    public let authorizedArtifactIdentity:
        ModelInstallArtifactIdentity?
    public let purpose: ModelPurpose
    public let action: ModelInstallQueueAction
    public let createdAt: String
    public let retryOfAttemptID: String?
    public private(set) var state: DownloadState
    public private(set) var resumableData: ModelInstallResumableData?

    public init(
        id: String,
        artifactID: String,
        authorizedArtifactIdentity:
            ModelInstallArtifactIdentity? = nil,
        purpose: ModelPurpose,
        action: ModelInstallQueueAction,
        createdAt: String,
        retryOfAttemptID: String? = nil,
        state: DownloadState,
        resumableData: ModelInstallResumableData? = nil
    ) {
        self.id = id
        self.artifactID = artifactID
        self.authorizedArtifactIdentity = authorizedArtifactIdentity
        self.purpose = purpose
        self.action = action
        self.createdAt = createdAt
        self.retryOfAttemptID = retryOfAttemptID
        self.state = DownloadState(
            modelID: artifactID,
            phase: state.phase,
            bytesDownloaded: state.bytesDownloaded,
            totalBytes: state.totalBytes,
            message: state.message,
            attemptID: id
        )
        self.resumableData = resumableData
    }

    mutating func update(
        state: DownloadState,
        resumableData: ModelInstallResumableData?
    ) {
        self.state = DownloadState(
            modelID: artifactID,
            phase: state.phase,
            bytesDownloaded: state.bytesDownloaded,
            totalBytes: state.totalBytes,
            message: state.message,
            attemptID: id
        )
        if let resumableData {
            self.resumableData = resumableData
        }
    }

    mutating func discardRetainedData() {
        resumableData = nil
    }
}

public enum ModelInstallQueueError: Error, Equatable {
    case duplicateAttemptID(String)
    case attemptNotFound(String)
    case attemptIsNotFIFOHead(String)
    case modelIdentityMismatch(expected: String, actual: String)
    case transitionNotAllowed(from: DownloadPhase, to: DownloadPhase)
    case retryNotAllowed(String)
    case retainedDataNotFound(String)
}

public struct ModelInstallQueue: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public private(set) var attempts: [ModelInstallQueueAttempt]

    public init(
        schemaVersion: Int = 1,
        attempts: [ModelInstallQueueAttempt] = []
    ) {
        self.schemaVersion = schemaVersion
        self.attempts = attempts
    }

    public var headAttempt: ModelInstallQueueAttempt? {
        attempts.first { !$0.state.phase.isTerminal }
    }

    public var nextRunnableAttempt: ModelInstallQueueAttempt? {
        guard let headAttempt, headAttempt.state.phase == .queued else {
            return nil
        }
        return headAttempt
    }

    public var activeAttempt: ModelInstallQueueAttempt? {
        attempts.first { $0.state.phase.isPipelineActive }
    }

    public var latestStatesByArtifactID: [String: DownloadState] {
        var states: [String: DownloadState] = [:]
        for attempt in attempts.reversed() where states[attempt.artifactID] == nil {
            states[attempt.artifactID] = attempt.state
        }
        var projectedNonterminalArtifactIDs: Set<String> = []
        for attempt in attempts where !attempt.state.phase.isTerminal {
            if projectedNonterminalArtifactIDs.insert(attempt.artifactID).inserted {
                states[attempt.artifactID] = attempt.state
            }
        }
        for attempt in attempts where attempt.state.phase.isPipelineActive {
            states[attempt.artifactID] = attempt.state
        }
        return states
    }

    public func attempt(id: String) -> ModelInstallQueueAttempt? {
        attempts.first { $0.id == id }
    }

    @discardableResult
    public mutating func authorize(
        artifactID: String,
        authorizedArtifactIdentity:
            ModelInstallArtifactIdentity? = nil,
        purpose: ModelPurpose,
        action: ModelInstallQueueAction,
        attemptID: String,
        createdAt: String
    ) throws -> ModelInstallQueueAttempt {
        guard attempt(id: attemptID) == nil else {
            throw ModelInstallQueueError.duplicateAttemptID(attemptID)
        }
        let attempt = ModelInstallQueueAttempt(
            id: attemptID,
            artifactID: artifactID,
            authorizedArtifactIdentity: authorizedArtifactIdentity,
            purpose: purpose,
            action: action,
            createdAt: createdAt,
            state: DownloadState(
                modelID: artifactID,
                phase: .queued,
                message: "Queued",
                attemptID: attemptID
            )
        )
        attempts.append(attempt)
        return attempt
    }

    public mutating func transition(
        attemptID: String,
        to state: DownloadState,
        resumableData: ModelInstallResumableData? = nil
    ) throws {
        guard let index = attempts.firstIndex(where: { $0.id == attemptID }) else {
            throw ModelInstallQueueError.attemptNotFound(attemptID)
        }
        let attempt = attempts[index]
        guard state.modelID == attempt.artifactID else {
            throw ModelInstallQueueError.modelIdentityMismatch(
                expected: attempt.artifactID,
                actual: state.modelID
            )
        }
        guard Self.allowsTransition(
            from: attempt.state.phase,
            to: state.phase
        ) else {
            throw ModelInstallQueueError.transitionNotAllowed(
                from: attempt.state.phase,
                to: state.phase
            )
        }
        if state.phase.isPipelineActive {
            guard headAttempt?.id == attemptID else {
                throw ModelInstallQueueError.attemptIsNotFIFOHead(attemptID)
            }
            guard activeAttempt == nil || activeAttempt?.id == attemptID else {
                throw ModelInstallQueueError.attemptIsNotFIFOHead(attemptID)
            }
        }
        attempts[index].update(
            state: state,
            resumableData: resumableData
        )
    }

    public mutating func cancel(attemptID: String) throws {
        guard let attempt = attempt(id: attemptID) else {
            throw ModelInstallQueueError.attemptNotFound(attemptID)
        }
        try transition(
            attemptID: attemptID,
            to: DownloadState(
                modelID: attempt.artifactID,
                phase: .cancelled,
                bytesDownloaded: attempt.state.bytesDownloaded,
                totalBytes: attempt.state.totalBytes,
                message: "Download cancelled.",
                attemptID: attemptID
            )
        )
    }

    public mutating func associateResumableData(
        _ resumableData: ModelInstallResumableData,
        with attemptID: String
    ) throws {
        guard let index = attempts.firstIndex(where: { $0.id == attemptID }) else {
            throw ModelInstallQueueError.attemptNotFound(attemptID)
        }
        let attempt = attempts[index]
        attempts[index].update(
            state: attempt.state,
            resumableData: resumableData
        )
    }

    public mutating func discardRetainedData(
        attemptID: String
    ) throws {
        guard let index = attempts.firstIndex(where: {
            $0.id == attemptID
        }),
        attempts[index].state.phase == .revoked,
        attempts[index].resumableData != nil
        else {
            throw ModelInstallQueueError.retainedDataNotFound(attemptID)
        }
        attempts[index].discardRetainedData()
    }

    @discardableResult
    public mutating func retry(
        attemptID: String,
        newAttemptID: String,
        createdAt: String
    ) throws -> ModelInstallQueueAttempt {
        guard let source = attempt(id: attemptID) else {
            throw ModelInstallQueueError.attemptNotFound(attemptID)
        }
        guard [.interrupted, .failed, .cancelled].contains(source.state.phase) else {
            throw ModelInstallQueueError.retryNotAllowed(attemptID)
        }
        guard attempt(id: newAttemptID) == nil else {
            throw ModelInstallQueueError.duplicateAttemptID(newAttemptID)
        }

        let retry = ModelInstallQueueAttempt(
            id: newAttemptID,
            artifactID: source.artifactID,
            authorizedArtifactIdentity:
                source.authorizedArtifactIdentity,
            purpose: source.purpose,
            action: source.action,
            createdAt: createdAt,
            retryOfAttemptID: source.id,
            state: DownloadState(
                modelID: source.artifactID,
                phase: .queued,
                bytesDownloaded: source.resumableData?.validatedBytes ?? 0,
                totalBytes: source.state.totalBytes,
                message: source.resumableData == nil
                    ? "Queued"
                    : "Queued with validated resumable data.",
                attemptID: newAttemptID
            ),
            resumableData: source.resumableData?.reassociated(
                from: source.id,
                to: newAttemptID
            )
        )
        attempts.append(retry)
        return retry
    }

    public func recoveredForRelaunch() -> ModelInstallQueue {
        let recovered = attempts.map { attempt -> ModelInstallQueueAttempt in
            guard attempt.state.phase.isPipelineActive else {
                return attempt
            }
            return ModelInstallQueueAttempt(
                id: attempt.id,
                artifactID: attempt.artifactID,
                authorizedArtifactIdentity:
                    attempt.authorizedArtifactIdentity,
                purpose: attempt.purpose,
                action: attempt.action,
                createdAt: attempt.createdAt,
                retryOfAttemptID: attempt.retryOfAttemptID,
                state: DownloadState(
                    modelID: attempt.artifactID,
                    phase: .queued,
                    bytesDownloaded: attempt.state.bytesDownloaded,
                    totalBytes: attempt.state.totalBytes,
                    message: "Queued after relaunch.",
                    attemptID: attempt.id
                ),
                resumableData: attempt.resumableData
            )
        }
        return ModelInstallQueue(
            schemaVersion: schemaVersion,
            attempts: recovered
        )
    }

    public static func allowsTransition(
        from source: DownloadPhase,
        to destination: DownloadPhase
    ) -> Bool {
        if source == destination {
            return !source.isTerminal
        }

        switch source {
        case .queued:
            return [
                .paused,
                .waitingForNetwork,
                .waitingForCatalogCheck,
                .checkingSpace,
                .cancelled,
                .revoked,
            ].contains(destination)
        case .paused:
            return [.queued, .cancelled, .revoked].contains(destination)
        case .waitingForNetwork:
            return [
                .queued,
                .waitingForCatalogCheck,
                .cancelled,
                .revoked,
            ].contains(destination)
        case .waitingForCatalogCheck:
            return [
                .queued,
                .waitingForNetwork,
                .cancelled,
                .revoked,
            ].contains(destination)
        case .checkingSpace:
            return [
                .downloading,
                .waitingForNetwork,
                .waitingForCatalogCheck,
                .installed,
                .failed,
                .cancelled,
                .revoked,
            ].contains(destination)
        case .downloading:
            return [
                .paused,
                .waitingForNetwork,
                .waitingForCatalogCheck,
                .interrupted,
                .verifying,
                .installed,
                .failed,
                .cancelled,
                .revoked,
            ].contains(destination)
        case .verifying:
            return [
                .installing,
                .installed,
                .failed,
                .cancelled,
                .revoked,
            ].contains(destination)
        case .installing:
            return [.installed, .failed, .revoked].contains(destination)
        case .interrupted, .installed, .failed, .cancelled, .revoked:
            return false
        }
    }
}

public struct ModelInstallQueueStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> ModelInstallQueue {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ModelInstallQueue()
        }
        return try JSONDecoder().decode(
            ModelInstallQueue.self,
            from: Data(contentsOf: fileURL)
        )
    }

    public func loadForRelaunch() throws -> ModelInstallQueue {
        try load().recoveredForRelaunch()
    }

    public func save(_ queue: ModelInstallQueue) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(queue).write(to: fileURL, options: [.atomic])
    }
}

public struct ModelInstallResumableDataInspector: @unchecked Sendable {
    private let layout: ModelStorageLayout
    private let fileManager: FileManager

    public init(
        layout: ModelStorageLayout,
        fileManager: FileManager = .default
    ) {
        self.layout = layout
        self.fileManager = fileManager
    }

    public func inspect(
        for attempt: ModelInstallQueueAttempt,
        expectedFiles: [ModelFile]
    ) throws -> ModelInstallResumableData? {
        let validatedStagingFiles =
            try validatedDirectoryStagingFiles(
                for: attempt,
                expectedFiles: expectedFiles
            )
        let reusable = try ModelReusableStorageInspector.inspect(
            layout: layout,
            modelID: attempt.artifactID,
            expectedFiles: expectedFiles,
            additionalValidatedFiles: validatedStagingFiles,
            fileManager: fileManager
        )
        guard reusable.storage.creditBytes > 0,
              reusable.fileCount > 0
        else {
            return nil
        }
        return ModelInstallResumableData(
            sourceAttemptID: attempt.id,
            associatedAttemptID: attempt.id,
            validatedBytes: reusable.storage.creditBytes,
            fileCount: reusable.fileCount,
            filenames: expectedFiles.map(\.filename)
        )
    }

    private func validatedDirectoryStagingFiles(
        for attempt: ModelInstallQueueAttempt,
        expectedFiles: [ModelFile]
    ) throws -> [(url: URL, logicalBytes: Int64)] {
        guard attempt.state.phase == .revoked,
              fileManager.fileExists(
                  atPath: layout.downloadsDirectory.path
              )
        else {
            return []
        }
        _ = try layout.installedModelDirectory(
            modelID: attempt.artifactID
        )
        let prefix = ".\(attempt.artifactID).installing-"
        let stagingDirectories = try fileManager.contentsOfDirectory(
            at: layout.downloadsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter {
            $0.lastPathComponent.hasPrefix(prefix)
                && (
                    try? $0.resourceValues(
                        forKeys: [.isDirectoryKey]
                    ).isDirectory
                ) == true
        }
        var result: [(url: URL, logicalBytes: Int64)] = []
        for stagingDirectory in stagingDirectories {
            for file in expectedFiles {
                let stagedURL = try layout.artifactURL(
                    in: stagingDirectory,
                    relativePath: file.relativePath ?? file.filename
                )
                guard let size = try? stagedURL.resourceValues(
                    forKeys: [.fileSizeKey]
                ).fileSize,
                Int64(size) == file.sizeBytes
                else {
                    continue
                }
                result.append(
                    (url: stagedURL, logicalBytes: file.sizeBytes)
                )
            }
        }
        return result
    }
}

public struct ModelInstallRetainedDataRemover: @unchecked Sendable {
    private let layout: ModelStorageLayout
    private let fileManager: FileManager

    public init(
        layout: ModelStorageLayout,
        fileManager: FileManager = .default
    ) {
        self.layout = layout
        self.fileManager = fileManager
    }

    public func remove(
        modelID: String,
        expectedFiles: [ModelFile]
    ) throws {
        try remove(
            modelID: modelID,
            filenames: expectedFiles.map(\.filename)
        )
    }

    public func remove(
        modelID: String,
        filenames: [String]
    ) throws {
        let installedDirectory = try layout.installedModelDirectory(
            modelID: modelID
        )
        if filenames.isEmpty {
            try removeMetadataAttributedDownloads(modelID: modelID)
        }
        for filename in filenames {
            let partialURL = try layout.temporaryDownloadURL(
                modelID: modelID,
                filename: filename
            )
            let metadataURL = try layout.downloadResumeMetadataURL(
                modelID: modelID,
                filename: filename
            )
            try removeIfPresent(partialURL)
            try removeIfPresent(metadataURL)
        }

        try removeDirectoryStaging(modelID: modelID)
        try removeRetainedArchives(modelID: modelID)
        for filename in filenames {
            try removeMatchingChildren(
                in: installedDirectory,
                namePrefix: ".\(filename).installing-"
            )
        }
    }

    public func removeDirectoryStaging(modelID: String) throws {
        _ = try layout.installedModelDirectory(modelID: modelID)
        try removeMatchingChildren(
            in: layout.downloadsDirectory,
            namePrefix: ".\(modelID).installing-"
        )
    }

    private func removeRetainedArchives(modelID: String) throws {
        _ = try layout.installedModelDirectory(modelID: modelID)
        try removeMatchingChildren(
            in: layout.downloadsDirectory,
            namePrefix: ".\(modelID).retained-"
        )
    }

    private func removeMatchingChildren(
        in directory: URL,
        namePrefix: String
    ) throws {
        guard fileManager.fileExists(atPath: directory.path) else {
            return
        }
        let children = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants]
        )
        for child in children
        where child.lastPathComponent.hasPrefix(namePrefix) {
            try fileManager.removeItem(at: child)
        }
    }

    private func removeMetadataAttributedDownloads(
        modelID: String
    ) throws {
        guard fileManager.fileExists(
            atPath: layout.downloadsDirectory.path
        ) else {
            return
        }
        let children = try fileManager.contentsOfDirectory(
            at: layout.downloadsDirectory,
            includingPropertiesForKeys: nil
        )
        for metadataURL in children
        where metadataURL.lastPathComponent.hasSuffix(
            ".partial.resume.json"
        ) {
            guard let data = try? Data(contentsOf: metadataURL),
                  let metadata = try? JSONDecoder().decode(
                      DownloadResumeMetadata.self,
                      from: data
                  ),
                  metadata.modelID == modelID
            else {
                continue
            }
            let partialURL = metadataURL
                .deletingPathExtension()
                .deletingPathExtension()
            try removeIfPresent(partialURL)
            try removeIfPresent(metadataURL)
        }
    }

    private func removeIfPresent(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }
}

public struct ModelInstallRetainedDataIsolator: @unchecked Sendable {
    private let layout: ModelStorageLayout
    private let fileManager: FileManager

    public init(
        layout: ModelStorageLayout,
        fileManager: FileManager = .default
    ) {
        self.layout = layout
        self.fileManager = fileManager
    }

    public func isolate(
        modelID: String,
        filenames: [String]
    ) throws {
        try isolateDirectoryStaging(modelID: modelID)
        let archiveDirectory =
            try layout.temporaryRetainedDataDirectory(modelID: modelID)
        var movedData = false
        for filename in Array(Set(filenames)).sorted() {
            let sourceURLs = [
                try layout.temporaryDownloadURL(
                    modelID: modelID,
                    filename: filename
                ),
                try layout.downloadResumeMetadataURL(
                    modelID: modelID,
                    filename: filename
                ),
            ]
            for sourceURL in sourceURLs
            where fileManager.fileExists(atPath: sourceURL.path) {
                if !movedData {
                    try fileManager.createDirectory(
                        at: archiveDirectory,
                        withIntermediateDirectories: true
                    )
                }
                let destinationURL = try layout.artifactURL(
                    in: archiveDirectory,
                    relativePath: sourceURL.lastPathComponent
                )
                try fileManager.moveItem(
                    at: sourceURL,
                    to: destinationURL
                )
                movedData = true
            }
        }
    }

    private func isolateDirectoryStaging(modelID: String) throws {
        _ = try layout.installedModelDirectory(modelID: modelID)
        guard fileManager.fileExists(
            atPath: layout.downloadsDirectory.path
        ) else {
            return
        }
        let prefix = ".\(modelID).installing-"
        let stagingDirectories = try fileManager.contentsOfDirectory(
            at: layout.downloadsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsSubdirectoryDescendants]
        ).filter {
            $0.lastPathComponent.hasPrefix(prefix)
                && (
                    try? $0.resourceValues(
                        forKeys: [.isDirectoryKey]
                    ).isDirectory
                ) == true
        }
        for stagingDirectory in stagingDirectories {
            try fileManager.moveItem(
                at: stagingDirectory,
                to: layout.temporaryRetainedDataDirectory(
                    modelID: modelID
                )
            )
        }
    }
}
