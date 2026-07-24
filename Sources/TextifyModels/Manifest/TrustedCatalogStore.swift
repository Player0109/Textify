import Foundation

public enum TrustedCatalogSecuritySeverity: String, Codable, Equatable, Sendable {
    case high
}

public enum TrustedCatalogSecurityReason: String, Codable, Equatable, Sendable {
    case invalidSignature = "invalid_signature"
    case rollback
    case strictDecoding = "strict_decoding"
    case schemaValidation = "schema_validation"
    case cacheCorruption = "cache_corruption"
    case bundledCatalogInvalid = "bundled_catalog_invalid"
}

public struct TrustedCatalogSecurityIssue: Codable, Equatable, Sendable {
    public let severity: TrustedCatalogSecuritySeverity
    public let reason: TrustedCatalogSecurityReason
    public let candidateRevision: String?
    public let highestAcceptedRevision: String?

    public init(
        reason: TrustedCatalogSecurityReason,
        candidateRevision: String? = nil,
        highestAcceptedRevision: String? = nil
    ) {
        severity = .high
        self.reason = reason
        self.candidateRevision = candidateRevision
        self.highestAcceptedRevision = highestAcceptedRevision
    }
}

public struct TrustedCatalogSnapshot: Equatable, Sendable {
    public let manifestData: Data
    public let signatureData: Data
    public let manifest: ModelManifest

    public var revision: String {
        manifest.generatedAt
    }

    public init(
        manifestData: Data,
        signatureData: Data,
        verifier: ManifestVerifier
    ) throws {
        let manifest = try verifier.verify(
            manifestData: manifestData,
            signatureData: signatureData
        )
        try ProductionModelPolicy.validateProductionManifest(manifest)
        self.manifestData = manifestData
        self.signatureData = signatureData
        self.manifest = manifest
    }
}

public struct TrustedCatalogStoredState: Equatable, Sendable {
    public var highestAcceptedRevision: String?
    public var presentedSnapshot: TrustedCatalogSnapshot?
    public var stagedSnapshot: TrustedCatalogSnapshot?
    public var securityIssue: TrustedCatalogSecurityIssue?
    public var lastSuccessfulCatalogIntegrityCheckAt: Date?

    public init(
        highestAcceptedRevision: String? = nil,
        presentedSnapshot: TrustedCatalogSnapshot? = nil,
        stagedSnapshot: TrustedCatalogSnapshot? = nil,
        securityIssue: TrustedCatalogSecurityIssue? = nil,
        lastSuccessfulCatalogIntegrityCheckAt: Date? = nil
    ) {
        self.highestAcceptedRevision = highestAcceptedRevision
        self.presentedSnapshot = presentedSnapshot
        self.stagedSnapshot = stagedSnapshot
        self.securityIssue = securityIssue
        self.lastSuccessfulCatalogIntegrityCheckAt =
            lastSuccessfulCatalogIntegrityCheckAt
    }
}

public enum TrustedCatalogStoreError: Error, Equatable {
    case unsupportedArchiveVersion(Int)
    case invalidRevision(String)
    case invalidRevisionOrder
}

public struct TrustedCatalogStore {
    private static let archiveVersion = 1

    public let fileURL: URL
    private let verifier: ManifestVerifier
    private let fileManager: FileManager

    public init(
        fileURL: URL,
        verifier: ManifestVerifier,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.verifier = verifier
        self.fileManager = fileManager
    }

    public func load() throws -> TrustedCatalogStoredState {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return TrustedCatalogStoredState()
        }
        let archive = try JSONDecoder().decode(
            Archive.self,
            from: Data(contentsOf: fileURL)
        )
        guard archive.archiveVersion == Self.archiveVersion else {
            throw TrustedCatalogStoreError.unsupportedArchiveVersion(
                archive.archiveVersion
            )
        }
        let presented = try archive.presentedSnapshot.map(snapshot(from:))
        let staged = try archive.stagedSnapshot.map(snapshot(from:))
        let state = TrustedCatalogStoredState(
            highestAcceptedRevision: archive.highestAcceptedRevision,
            presentedSnapshot: presented,
            stagedSnapshot: staged,
            securityIssue: archive.securityIssue,
            lastSuccessfulCatalogIntegrityCheckAt:
                archive.lastSuccessfulCatalogIntegrityCheckAt
        )
        try Self.validateRevisionOrder(state)
        return state
    }

    public func save(_ state: TrustedCatalogStoredState) throws {
        try Self.validateRevisionOrder(state)
        let archive = Archive(
            archiveVersion: Self.archiveVersion,
            highestAcceptedRevision: state.highestAcceptedRevision,
            presentedSnapshot: state.presentedSnapshot.map(StoredSnapshot.init),
            stagedSnapshot: state.stagedSnapshot.map(StoredSnapshot.init),
            securityIssue: state.securityIssue,
            lastSuccessfulCatalogIntegrityCheckAt:
                state.lastSuccessfulCatalogIntegrityCheckAt
        )
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(archive).write(to: fileURL, options: .atomic)
    }

    private func snapshot(from stored: StoredSnapshot) throws -> TrustedCatalogSnapshot {
        try TrustedCatalogSnapshot(
            manifestData: stored.manifestData,
            signatureData: stored.signatureData,
            verifier: verifier
        )
    }

    private static func validateRevisionOrder(
        _ state: TrustedCatalogStoredState
    ) throws {
        let revisions = [
            state.highestAcceptedRevision,
            state.presentedSnapshot?.revision,
            state.stagedSnapshot?.revision,
        ].compactMap { $0 }
        for revision in revisions where catalogDate(revision) == nil {
            throw TrustedCatalogStoreError.invalidRevision(revision)
        }
        guard let highest = state.highestAcceptedRevision else {
            guard state.presentedSnapshot == nil, state.stagedSnapshot == nil else {
                throw TrustedCatalogStoreError.invalidRevisionOrder
            }
            return
        }
        let highestDate = catalogDate(highest)!
        guard state.presentedSnapshot.map({
            catalogDate($0.revision)! <= highestDate
        }) ?? true,
        state.stagedSnapshot.map({
            catalogDate($0.revision)! <= highestDate
        }) ?? true else {
            throw TrustedCatalogStoreError.invalidRevisionOrder
        }
        if let staged = state.stagedSnapshot {
            guard staged.revision == highest else {
                throw TrustedCatalogStoreError.invalidRevisionOrder
            }
        } else {
            guard state.presentedSnapshot?.revision == highest else {
                throw TrustedCatalogStoreError.invalidRevisionOrder
            }
        }
    }

    static func catalogDate(_ revision: String) -> Date? {
        ISO8601DateFormatter().date(from: revision)
    }

    private struct Archive: Codable {
        let archiveVersion: Int
        let highestAcceptedRevision: String?
        let presentedSnapshot: StoredSnapshot?
        let stagedSnapshot: StoredSnapshot?
        let securityIssue: TrustedCatalogSecurityIssue?
        let lastSuccessfulCatalogIntegrityCheckAt: Date?
    }

    private struct StoredSnapshot: Codable {
        let manifestData: Data
        let signatureData: Data

        init(_ snapshot: TrustedCatalogSnapshot) {
            manifestData = snapshot.manifestData
            signatureData = snapshot.signatureData
        }
    }
}
