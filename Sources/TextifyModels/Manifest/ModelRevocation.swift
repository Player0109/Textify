import CryptoKit
import Foundation

public enum ModelRevocationDigestAlgorithm: String, Codable, Equatable, Sendable {
    case sha256
}

public enum ModelRevocationDigestScope: Equatable, Sendable {
    case singleFilePayload
    case canonicalLayout(version: Int)
    case managedFile(relativePath: String)
}

extension ModelRevocationDigestScope: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ScopeType.self, forKey: .type)
        switch type {
        case .singleFilePayload:
            try StrictJSONKeys.validate(
                decoder: decoder,
                allowedKeys: [CodingKeys.type.stringValue]
            )
            self = .singleFilePayload
        case .canonicalLayout:
            try StrictJSONKeys.validate(
                decoder: decoder,
                allowedKeys: [
                    CodingKeys.type.stringValue,
                    CodingKeys.version.stringValue,
                ]
            )
            self = .canonicalLayout(
                version: try container.decode(Int.self, forKey: .version)
            )
        case .managedFile:
            try StrictJSONKeys.validate(
                decoder: decoder,
                allowedKeys: [
                    CodingKeys.type.stringValue,
                    CodingKeys.relativePath.stringValue,
                ]
            )
            self = .managedFile(
                relativePath: try container.decode(
                    String.self,
                    forKey: .relativePath
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .singleFilePayload:
            try container.encode(
                ScopeType.singleFilePayload,
                forKey: .type
            )
        case let .canonicalLayout(version):
            try container.encode(
                ScopeType.canonicalLayout,
                forKey: .type
            )
            try container.encode(version, forKey: .version)
        case let .managedFile(relativePath):
            try container.encode(ScopeType.managedFile, forKey: .type)
            try container.encode(relativePath, forKey: .relativePath)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case version
        case relativePath
    }

    private enum ScopeType: String, Codable {
        case singleFilePayload = "single_file_payload"
        case canonicalLayout = "canonical_layout"
        case managedFile = "managed_file"
    }
}

public struct ModelRevocationDigestTarget: Codable, Equatable, Sendable {
    public let algorithm: ModelRevocationDigestAlgorithm
    public let value: String
    public let scope: ModelRevocationDigestScope

    public init(
        algorithm: ModelRevocationDigestAlgorithm,
        value: String,
        scope: ModelRevocationDigestScope
    ) {
        self.algorithm = algorithm
        self.value = value
        self.scope = scope
    }

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        algorithm = try container.decode(
            ModelRevocationDigestAlgorithm.self,
            forKey: .algorithm
        )
        value = try container.decode(String.self, forKey: .value)
        scope = try container.decode(
            ModelRevocationDigestScope.self,
            forKey: .scope
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case algorithm
        case value
        case scope
    }
}

public struct ModelRevocationRecord: Codable, Equatable, Sendable {
    public let recordID: String
    public let exactArtifactID: String?
    public let contentDigest: ModelRevocationDigestTarget?

    public init(
        recordID: String,
        exactArtifactID: String? = nil,
        contentDigest: ModelRevocationDigestTarget? = nil
    ) {
        self.recordID = recordID
        self.exactArtifactID = exactArtifactID
        self.contentDigest = contentDigest
    }

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordID = try container.decode(String.self, forKey: .recordID)
        exactArtifactID = try container.decodeIfPresent(
            String.self,
            forKey: .exactArtifactID
        )
        contentDigest = try container.decodeIfPresent(
            ModelRevocationDigestTarget.self,
            forKey: .contentDigest
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recordID, forKey: .recordID)
        if let exactArtifactID {
            try container.encode(exactArtifactID, forKey: .exactArtifactID)
        } else {
            try container.encodeNil(forKey: .exactArtifactID)
        }
        if let contentDigest {
            try container.encode(contentDigest, forKey: .contentDigest)
        } else {
            try container.encodeNil(forKey: .contentDigest)
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case recordID
        case exactArtifactID
        case contentDigest
    }
}

public struct ModelRevocationEnvelope: Codable, Equatable, Sendable {
    public let revocationVersion: Int
    public let generatedAt: String
    public let records: [ModelRevocationRecord]

    public init(
        revocationVersion: Int,
        generatedAt: String,
        records: [ModelRevocationRecord]
    ) {
        self.revocationVersion = revocationVersion
        self.generatedAt = generatedAt
        self.records = records
    }

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revocationVersion = try container.decode(
            Int.self,
            forKey: .revocationVersion
        )
        generatedAt = try container.decode(String.self, forKey: .generatedAt)
        records = try container.decode(
            [ModelRevocationRecord].self,
            forKey: .records
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case revocationVersion
        case generatedAt
        case records
    }
}

public enum ModelRevocationPolicyError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalidGeneratedAt(String)
    case duplicateRecordID(String)
    case invalidRecordID(String)
    case missingTarget(String)
    case invalidArtifactID(String)
    case invalidDigest(String)
    case unsupportedCanonicalLayoutVersion(Int)
    case unsafeManagedRelativePath(String)
}

public enum ModelRevocationPolicy {
    public static func validate(_ envelope: ModelRevocationEnvelope) throws {
        guard envelope.revocationVersion == 1 else {
            throw ModelRevocationPolicyError.unsupportedVersion(
                envelope.revocationVersion
            )
        }
        guard ISO8601DateFormatter().date(from: envelope.generatedAt) != nil else {
            throw ModelRevocationPolicyError.invalidGeneratedAt(
                envelope.generatedAt
            )
        }
        var recordIDs = Set<String>()
        for record in envelope.records {
            guard isPathSafeIdentifier(record.recordID) else {
                throw ModelRevocationPolicyError.invalidRecordID(
                    record.recordID
                )
            }
            guard recordIDs.insert(record.recordID).inserted else {
                throw ModelRevocationPolicyError.duplicateRecordID(
                    record.recordID
                )
            }
            guard record.exactArtifactID != nil
                || record.contentDigest != nil
            else {
                throw ModelRevocationPolicyError.missingTarget(record.recordID)
            }
            if let artifactID = record.exactArtifactID,
               !isPathSafeIdentifier(artifactID) {
                throw ModelRevocationPolicyError.invalidArtifactID(artifactID)
            }
            if let digest = record.contentDigest {
                guard digest.value.count == 64,
                      digest.value.unicodeScalars.allSatisfy({
                          CharacterSet(
                            charactersIn: "0123456789abcdef"
                          ).contains($0)
                      })
                else {
                    throw ModelRevocationPolicyError.invalidDigest(
                        digest.value
                    )
                }
                switch digest.scope {
                case .singleFilePayload:
                    break
                case let .canonicalLayout(version):
                    guard version == 1 else {
                        throw ModelRevocationPolicyError
                            .unsupportedCanonicalLayoutVersion(version)
                    }
                case let .managedFile(relativePath):
                    guard isSafeRelativePath(relativePath) else {
                        throw ModelRevocationPolicyError
                            .unsafeManagedRelativePath(relativePath)
                    }
                }
            }
        }
    }

    private static func isPathSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("..")
            && !value.contains("/")
            && !value.contains("\\")
            && !value.contains(":")
            && value.range(
                of: #"^[A-Za-z0-9._-]+$"#,
                options: .regularExpression
            ) != nil
    }

    private static func isSafeRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.hasSuffix("/"),
              !value.contains("\\")
        else {
            return false
        }
        return value.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).allSatisfy {
            isPathSafeIdentifier(String($0))
        }
    }
}

public struct ModelRevocationSignature: Codable, Equatable, Sendable {
    public let signatureVersion: Int
    public let signatureType: String
    public let algorithm: String
    public let keyId: String
    public let revocationFile: String
    public let contentType: String
    public let contentSHA256: String
    public let signature: String

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        signatureVersion = try container.decode(
            Int.self,
            forKey: .signatureVersion
        )
        signatureType = try container.decode(
            String.self,
            forKey: .signatureType
        )
        algorithm = try container.decode(String.self, forKey: .algorithm)
        keyId = try container.decode(String.self, forKey: .keyId)
        revocationFile = try container.decode(
            String.self,
            forKey: .revocationFile
        )
        contentType = try container.decode(String.self, forKey: .contentType)
        contentSHA256 = try container.decode(
            String.self,
            forKey: .contentSHA256
        )
        signature = try container.decode(String.self, forKey: .signature)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case signatureVersion
        case signatureType
        case algorithm
        case keyId
        case revocationFile
        case contentType
        case contentSHA256
        case signature
    }
}

public enum ModelRevocationVerificationError: Error, Equatable {
    case unsupportedSignatureVersion(Int)
    case unsupportedSignatureType(String)
    case unsupportedAlgorithm(String)
    case unknownKeyID(String)
    case unexpectedRevocationFile(String)
    case unsupportedContentType(String)
    case contentTypeVersionMismatch
    case contentHashMismatch
    case invalidPublicKey
    case invalidSignatureEncoding
    case signatureRejected
}

public struct ModelRevocationVerifier: Sendable {
    public static let signatureType =
        "io.github.Player0109.Textify.model-revocations"
    public static let algorithm = "Ed25519"
    public static let revocationFile = "revocations.json"
    public static let contentTypeV1 =
        "application/vnd.textify.model-revocations+json;version=1"

    private let trustedKeys: [TrustedModelManifestKey]

    public init(trustedKeys: [TrustedModelManifestKey]) {
        self.trustedKeys = trustedKeys
    }

    public func verify(
        revocationData: Data,
        signatureData: Data
    ) throws -> ModelRevocationEnvelope {
        let signature = try JSONDecoder().decode(
            ModelRevocationSignature.self,
            from: signatureData
        )
        guard signature.signatureVersion == 1 else {
            throw ModelRevocationVerificationError
                .unsupportedSignatureVersion(signature.signatureVersion)
        }
        guard signature.signatureType == Self.signatureType else {
            throw ModelRevocationVerificationError
                .unsupportedSignatureType(signature.signatureType)
        }
        guard signature.algorithm == Self.algorithm else {
            throw ModelRevocationVerificationError
                .unsupportedAlgorithm(signature.algorithm)
        }
        guard signature.revocationFile == Self.revocationFile else {
            throw ModelRevocationVerificationError
                .unexpectedRevocationFile(signature.revocationFile)
        }
        guard let contentTypeVersion = Self.version(
            from: signature.contentType
        ) else {
            throw ModelRevocationVerificationError
                .unsupportedContentType(signature.contentType)
        }
        let publicKey = try trustedPublicKey(for: signature.keyId)
        guard Self.sha256Hex(revocationData) == signature.contentSHA256 else {
            throw ModelRevocationVerificationError.contentHashMismatch
        }
        guard let signatureBytes = Self.decodeBase64URLNoPadding(
            signature.signature
        ) else {
            throw ModelRevocationVerificationError.invalidSignatureEncoding
        }
        let payload = Self.canonicalPayload(signature)
        guard publicKey.isValidSignature(signatureBytes, for: payload) else {
            throw ModelRevocationVerificationError.signatureRejected
        }
        let bodyVersion = try JSONDecoder().decode(
            RevocationVersionEnvelope.self,
            from: revocationData
        ).revocationVersion
        guard bodyVersion == contentTypeVersion else {
            throw ModelRevocationVerificationError
                .contentTypeVersionMismatch
        }
        let envelope = try JSONDecoder().decode(
            ModelRevocationEnvelope.self,
            from: revocationData
        )
        try ModelRevocationPolicy.validate(envelope)
        return envelope
    }

    private func trustedPublicKey(
        for keyID: String
    ) throws -> Curve25519.Signing.PublicKey {
        guard let key = trustedKeys.first(where: { $0.keyId == keyID }) else {
            throw ModelRevocationVerificationError.unknownKeyID(keyID)
        }
        guard let data = Data(base64Encoded: key.publicKeyBase64) else {
            throw ModelRevocationVerificationError.invalidSignatureEncoding
        }
        do {
            return try Curve25519.Signing.PublicKey(
                rawRepresentation: data
            )
        } catch {
            throw ModelRevocationVerificationError.invalidPublicKey
        }
    }

    private static func canonicalPayload(
        _ signature: ModelRevocationSignature
    ) -> Data {
        Data(
            """
            TEXTIFY-MODEL-REVOCATIONS-SIGNATURE-V1
            signatureVersion=\(signature.signatureVersion)
            signatureType=\(signature.signatureType)
            algorithm=\(signature.algorithm)
            keyId=\(signature.keyId)
            revocationFile=\(signature.revocationFile)
            contentType=\(signature.contentType)
            contentSHA256=\(signature.contentSHA256)

            """.utf8
        )
    }

    private static func version(from contentType: String) -> Int? {
        let prefix =
            "application/vnd.textify.model-revocations+json;version="
        guard contentType.hasPrefix(prefix) else {
            return nil
        }
        let suffix = contentType.dropFirst(prefix.count)
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else {
            return nil
        }
        return Int(suffix)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func decodeBase64URLNoPadding(_ value: String) -> Data? {
        guard !value.isEmpty,
              !value.contains("="),
              value.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0)
                      || $0 == "-"
                      || $0 == "_"
              })
        else {
            return nil
        }
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64.append(
            String(repeating: "=", count: (4 - base64.count % 4) % 4)
        )
        return Data(base64Encoded: base64)
    }
}

public struct TrustedModelRevocationSnapshot: Equatable, Sendable {
    public let revocationData: Data
    public let signatureData: Data
    public let envelope: ModelRevocationEnvelope
    public let revisionDate: Date

    public var revision: String {
        envelope.generatedAt
    }

    public init(
        revocationData: Data,
        signatureData: Data,
        verifier: ModelRevocationVerifier
    ) throws {
        envelope = try verifier.verify(
            revocationData: revocationData,
            signatureData: signatureData
        )
        revisionDate = ISO8601DateFormatter().date(
            from: envelope.generatedAt
        )!
        self.revocationData = revocationData
        self.signatureData = signatureData
    }
}

public struct ModelRevocationDownloader {
    private let transport: any DownloadTransport
    private let verifier: ModelRevocationVerifier

    public init(
        transport: any DownloadTransport = URLSessionDownloadTransport(),
        verifier: ModelRevocationVerifier
    ) {
        self.transport = transport
        self.verifier = verifier
    }

    public func downloadSnapshot(
        revocationURL: URL,
        signatureURL: URL
    ) async throws -> TrustedModelRevocationSnapshot {
        try ModelDownloadURLPolicy.requireHTTPS(revocationURL)
        try ModelDownloadURLPolicy.requireHTTPS(signatureURL)

        let revocationResponse = try await transport.fetch(
            Self.anonymousGET(revocationURL)
        )
        let signatureResponse = try await transport.fetch(
            Self.anonymousGET(signatureURL)
        )
        return try TrustedModelRevocationSnapshot(
            revocationData: revocationResponse.data,
            signatureData: signatureResponse.data,
            verifier: verifier
        )
    }

    private static func anonymousGET(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpBody = nil
        request.allHTTPHeaderFields = [:]
        return request
    }
}

public struct ModelRevocationOverlay: Equatable, Sendable {
    public let records: [ModelRevocationRecord]
    private let retainedArtifactAliases: [ModelArtifactAlias]

    public init(
        records: [ModelRevocationRecord] = [],
        retainedArtifactAliases: [ModelArtifactAlias] = []
    ) {
        self.records = records
        self.retainedArtifactAliases = retainedArtifactAliases
    }

    public func isRevoked(
        artifactID: String,
        trustedManifest: ModelManifest?
    ) -> Bool {
        matchingRecordIDs(
            artifactIDs: [artifactID],
            digests: [],
            trustedManifest: trustedManifest
        ).isEmpty == false
    }

    public func isRevoked(
        model: ModelEntry,
        trustedManifest: ModelManifest?
    ) -> Bool {
        matchingRecordIDs(
            artifactIDs: [model.id],
            digests: Self.digests(for: model),
            trustedManifest: trustedManifest
        ).isEmpty == false
    }

    public func isRevoked(
        record: InstalledModelRecord,
        trustedManifest: ModelManifest?
    ) -> Bool {
        return matchingRecordIDs(
            artifactIDs: [record.model.id, record.storageModelID],
            digests: Self.digests(for: record),
            trustedManifest: trustedManifest
        ).isEmpty == false
    }

    public func matchingRecordIDs(
        for record: InstalledModelRecord,
        trustedManifest: ModelManifest?
    ) -> [String] {
        return matchingRecordIDs(
            artifactIDs: [record.model.id, record.storageModelID],
            digests: Self.digests(for: record),
            trustedManifest: trustedManifest
        )
    }

    private func matchingRecordIDs(
        artifactIDs: [String],
        digests: [ModelRevocationDigestTarget],
        trustedManifest: ModelManifest?
    ) -> [String] {
        let aliases = retainedArtifactAliases
            + (trustedManifest?.artifactAliases ?? [])
        return records.compactMap { record in
            let matchesID = record.exactArtifactID.map { targetID in
                artifactIDs.contains {
                    Self.equivalent(
                        targetID,
                        $0,
                        aliases: aliases
                    )
                }
            } ?? false
            let matchesDigest = record.contentDigest.map { target in
                digests.contains(target)
            } ?? false
            return matchesID || matchesDigest ? record.recordID : nil
        }
    }

    private static func equivalent(
        _ lhs: String,
        _ rhs: String,
        aliases: [ModelArtifactAlias]
    ) -> Bool {
        guard lhs != rhs else {
            return true
        }
        var pending = [lhs]
        var visited = Set<String>()
        while let artifactID = pending.popLast() {
            guard visited.insert(artifactID).inserted else {
                continue
            }
            for alias in aliases {
                if alias.aliasArtifactID == artifactID {
                    pending.append(alias.canonicalArtifactID)
                } else if alias.canonicalArtifactID == artifactID {
                    pending.append(alias.aliasArtifactID)
                }
            }
        }
        return visited.contains(rhs)
    }

    private static func digests(
        for record: InstalledModelRecord
    ) -> [ModelRevocationDigestTarget] {
        var result = digests(for: record.model)
        if let imported = record.identityHistory.customImport?.contentDigest {
            let digest = revocationDigest(from: imported)
            if !result.contains(digest) {
                result.append(digest)
            }
        }
        return result
    }

    private static func digests(
        for model: ModelEntry
    ) -> [ModelRevocationDigestTarget] {
        var result: [ModelRevocationDigestTarget] = []
        if model.runtime.artifactLayout == .singleFile,
           model.files.count == 1,
           let file = model.files.first {
            result.append(
                ModelRevocationDigestTarget(
                    algorithm: .sha256,
                    value: file.sha256,
                    scope: .singleFilePayload
                )
            )
        }
        result.append(
            ModelRevocationDigestTarget(
                algorithm: .sha256,
                value: model.artifactFingerprint(),
                scope: .canonicalLayout(version: 1)
            )
        )
        result.append(
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
        return result
    }

    private static func revocationDigest(
        from digest: ModelArtifactTypedDigest
    ) -> ModelRevocationDigestTarget {
        switch digest.type {
        case .singleFileSHA256:
            return ModelRevocationDigestTarget(
                algorithm: .sha256,
                value: digest.value,
                scope: .singleFilePayload
            )
        case .artifactFingerprintSHA256:
            return ModelRevocationDigestTarget(
                algorithm: .sha256,
                value: digest.value,
                scope: .canonicalLayout(version: 1)
            )
        }
    }
}

public enum TrustedModelRevocationStateError: Error, Equatable {
    case rollback(
        candidateRevision: String,
        highestAcceptedRevision: String
    )
    case conflictingRevision(String)
    case conflictingRecord(String)
}

public struct TrustedModelRevocationState: Equatable, Sendable {
    public let snapshots: [TrustedModelRevocationSnapshot]
    public let aliasSnapshots: [TrustedCatalogSnapshot]

    public init() {
        snapshots = []
        aliasSnapshots = []
    }

    public init(
        snapshots: [TrustedModelRevocationSnapshot],
        aliasSnapshots: [TrustedCatalogSnapshot] = []
    ) throws {
        var accepted: [TrustedModelRevocationSnapshot] = []
        for snapshot in snapshots {
            accepted = try Self.accept(snapshot, into: accepted)
        }
        self.snapshots = accepted
        self.aliasSnapshots = Self.aliasSnapshotsAddingEvidence(
            aliasSnapshots
        )
    }

    public var highestAcceptedRevision: String? {
        snapshots.last?.revision
    }

    public var overlay: ModelRevocationOverlay {
        var recordsByID: [String: ModelRevocationRecord] = [:]
        var orderedRecordIDs: [String] = []
        for record in snapshots.flatMap(\.envelope.records) {
            if recordsByID[record.recordID] == nil {
                orderedRecordIDs.append(record.recordID)
            }
            recordsByID[record.recordID] = record
        }
        return ModelRevocationOverlay(
            records: orderedRecordIDs.compactMap { recordsByID[$0] },
            retainedArtifactAliases: aliasSnapshots.flatMap {
                $0.manifest.artifactAliases
            }
        )
    }

    public func accepting(
        _ snapshot: TrustedModelRevocationSnapshot
    ) throws -> TrustedModelRevocationState {
        try TrustedModelRevocationState(
            validatedSnapshots: Self.accept(snapshot, into: snapshots),
            aliasSnapshots: aliasSnapshots
        )
    }

    public func retainingAliases(
        from snapshot: TrustedCatalogSnapshot
    ) -> TrustedModelRevocationState {
        let retained = Self.aliasSnapshotsAddingEvidence(
            aliasSnapshots + [snapshot]
        )
        guard retained != aliasSnapshots else {
            return self
        }
        return TrustedModelRevocationState(
            validatedSnapshots: snapshots,
            aliasSnapshots: retained
        )
    }

    private init(
        validatedSnapshots: [TrustedModelRevocationSnapshot],
        aliasSnapshots: [TrustedCatalogSnapshot]
    ) {
        snapshots = validatedSnapshots
        self.aliasSnapshots = aliasSnapshots
    }

    private static func accept(
        _ candidate: TrustedModelRevocationSnapshot,
        into snapshots: [TrustedModelRevocationSnapshot]
    ) throws -> [TrustedModelRevocationSnapshot] {
        guard let current = snapshots.last else {
            return [candidate]
        }
        if candidate.revisionDate < current.revisionDate {
            throw TrustedModelRevocationStateError.rollback(
                candidateRevision: candidate.revision,
                highestAcceptedRevision: current.revision
            )
        }
        if candidate.revisionDate == current.revisionDate {
            guard candidate == current else {
                throw TrustedModelRevocationStateError
                    .conflictingRevision(candidate.revision)
            }
            return snapshots
        }

        let recordsByID = snapshots
            .flatMap(\.envelope.records)
            .reduce(into: [String: ModelRevocationRecord]()) {
                $0[$1.recordID] = $1
            }
        for record in candidate.envelope.records {
            if let existing = recordsByID[record.recordID],
               existing != record {
                throw TrustedModelRevocationStateError
                    .conflictingRecord(record.recordID)
            }
        }
        return snapshots + [candidate]
    }

    private static func aliasSnapshotsAddingEvidence(
        _ snapshots: [TrustedCatalogSnapshot]
    ) -> [TrustedCatalogSnapshot] {
        var retainedAliases: [ModelArtifactAlias] = []
        return snapshots.reduce(into: []) { result, snapshot in
            let aliases = snapshot.manifest.artifactAliases
            guard aliases.contains(where: {
                !retainedAliases.contains($0)
            }) else {
                return
            }
            result.append(snapshot)
            for alias in aliases where !retainedAliases.contains(alias) {
                retainedAliases.append(alias)
            }
        }
    }

}

public enum TrustedModelRevocationStoreError: Error, Equatable {
    case unsupportedArchiveVersion(Int)
}

public struct TrustedModelRevocationStore {
    private static let archiveVersion = 1

    public let fileURL: URL
    private let verifier: ModelRevocationVerifier
    private let catalogVerifier: ManifestVerifier
    private let fileManager: FileManager

    public init(
        fileURL: URL,
        verifier: ModelRevocationVerifier,
        catalogVerifier: ManifestVerifier,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.verifier = verifier
        self.catalogVerifier = catalogVerifier
        self.fileManager = fileManager
    }

    public func load() throws -> TrustedModelRevocationState {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return TrustedModelRevocationState()
        }
        let archive = try JSONDecoder().decode(
            Archive.self,
            from: Data(contentsOf: fileURL)
        )
        guard archive.archiveVersion == Self.archiveVersion else {
            throw TrustedModelRevocationStoreError.unsupportedArchiveVersion(
                archive.archiveVersion
            )
        }
        let aliasSnapshots: [TrustedCatalogSnapshot]
        if let storedAliases = archive.aliasSnapshots,
           !storedAliases.isEmpty {
            aliasSnapshots = try storedAliases.map {
                try TrustedCatalogSnapshot(
                    manifestData: $0.manifestData,
                    signatureData: $0.signatureData,
                    verifier: catalogVerifier
                )
            }
        } else {
            aliasSnapshots = []
        }
        return try TrustedModelRevocationState(
            snapshots: try archive.snapshots.map {
                try TrustedModelRevocationSnapshot(
                    revocationData: $0.revocationData,
                    signatureData: $0.signatureData,
                    verifier: verifier
                )
            },
            aliasSnapshots: aliasSnapshots
        )
    }

    public func save(_ state: TrustedModelRevocationState) throws {
        let archive = Archive(
            archiveVersion: Self.archiveVersion,
            snapshots: state.snapshots.map(StoredSnapshot.init),
            aliasSnapshots: state.aliasSnapshots.map(
                StoredCatalogSnapshot.init
            )
        )
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(archive).write(to: fileURL, options: .atomic)
    }

    private struct Archive: Codable {
        let archiveVersion: Int
        let snapshots: [StoredSnapshot]
        let aliasSnapshots: [StoredCatalogSnapshot]?
    }

    private struct StoredSnapshot: Codable {
        let revocationData: Data
        let signatureData: Data

        init(_ snapshot: TrustedModelRevocationSnapshot) {
            revocationData = snapshot.revocationData
            signatureData = snapshot.signatureData
        }
    }

    private struct StoredCatalogSnapshot: Codable {
        let manifestData: Data
        let signatureData: Data

        init(_ snapshot: TrustedCatalogSnapshot) {
            manifestData = snapshot.manifestData
            signatureData = snapshot.signatureData
        }
    }
}

private struct RevocationVersionEnvelope: Decodable {
    let revocationVersion: Int
}
