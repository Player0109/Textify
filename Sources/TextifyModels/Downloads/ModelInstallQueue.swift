import Foundation

public enum ModelInstallQueueAction: String, Codable, Equatable, Sendable {
    case install
    case reinstall
}

public struct ModelInstallResumableData: Codable, Equatable, Sendable {
    public let sourceAttemptID: String
    public let associatedAttemptID: String
    public let validatedBytes: Int64
    public let fileCount: Int

    public init(
        sourceAttemptID: String,
        associatedAttemptID: String,
        validatedBytes: Int64,
        fileCount: Int
    ) {
        self.sourceAttemptID = sourceAttemptID
        self.associatedAttemptID = associatedAttemptID
        self.validatedBytes = max(0, validatedBytes)
        self.fileCount = max(0, fileCount)
    }

    func reassociated(
        from sourceAttemptID: String,
        to attemptID: String
    ) -> ModelInstallResumableData {
        ModelInstallResumableData(
            sourceAttemptID: sourceAttemptID,
            associatedAttemptID: attemptID,
            validatedBytes: validatedBytes,
            fileCount: fileCount
        )
    }
}

public struct ModelInstallQueueAttempt: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let artifactID: String
    public let purpose: ModelPurpose
    public let action: ModelInstallQueueAction
    public let createdAt: String
    public let retryOfAttemptID: String?
    public private(set) var state: DownloadState
    public private(set) var resumableData: ModelInstallResumableData?

    public init(
        id: String,
        artifactID: String,
        purpose: ModelPurpose,
        action: ModelInstallQueueAction,
        createdAt: String,
        retryOfAttemptID: String? = nil,
        state: DownloadState,
        resumableData: ModelInstallResumableData? = nil
    ) {
        self.id = id
        self.artifactID = artifactID
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
}

public enum ModelInstallQueueError: Error, Equatable {
    case duplicateAttemptID(String)
    case attemptNotFound(String)
    case attemptIsNotFIFOHead(String)
    case modelIdentityMismatch(expected: String, actual: String)
    case transitionNotAllowed(from: DownloadPhase, to: DownloadPhase)
    case retryNotAllowed(String)
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
        let reusable = try ModelReusableStorageInspector.inspect(
            layout: layout,
            modelID: attempt.artifactID,
            expectedFiles: expectedFiles,
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
            fileCount: reusable.fileCount
        )
    }

}
