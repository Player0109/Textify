import CryptoKit
import Foundation

public enum ManifestVerificationError: Error, Equatable {
    case unsupportedSignatureVersion(Int)
    case unsupportedSignatureType(String)
    case unsupportedAlgorithm(String)
    case unknownKeyId(String)
    case unexpectedManifestFile(String)
    case unsupportedContentType(String)
    case unsupportedManifestVersion(Int)
    case contentTypeManifestVersionMismatch
    case contentHashMismatch
    case invalidPublicKey
    case invalidSignatureEncoding
    case signatureRejected
    case legacyEnvelopeRejected
}

public struct TrustedModelManifestKey: Equatable, Sendable {
    public let keyId: String
    public let publicKeyBase64: String

    public init(keyId: String, publicKeyBase64: String) {
        self.keyId = keyId
        self.publicKeyBase64 = publicKeyBase64
    }
}

public struct LegacyManifestSignaturePolicy: Equatable, Sendable {
    public static let publishedV1_1 = LegacyManifestSignaturePolicy(
        keyId: "textify-model-manifest-2026-primary",
        contentSHA256: "6c25788e330108a819ee394fa6351d51f5e2a5782b2b2ce54e3a65b02b07e6ec"
    )

    public let keyId: String
    public let contentSHA256: String

    public init(keyId: String, contentSHA256: String) {
        self.keyId = keyId
        self.contentSHA256 = contentSHA256
    }
}

public struct ManifestVerifier {
    public static let algorithm = "Ed25519"
    public static let signatureType = "io.github.Player0109.Textify.model-manifest"
    public static let manifestFile = "manifest.json"
    public static let contentTypeV1 = ModelManifestSchemaVersion.v1.contentType
    public static let contentTypeV2 = ModelManifestSchemaVersion.v2.contentType
    public static let contentTypeV3 = ModelManifestSchemaVersion.v3.contentType
    public static let contentType = contentTypeV1

    private let trustedKeys: [TrustedModelManifestKey]
    private let legacyPolicy: LegacyManifestSignaturePolicy?

    public init(
        trustedKeys: [TrustedModelManifestKey],
        legacyPolicy: LegacyManifestSignaturePolicy? = nil
    ) {
        self.trustedKeys = trustedKeys
        self.legacyPolicy = legacyPolicy
    }

    public func verify(manifestData: Data, signatureData: Data) throws -> ModelManifest {
        if isLegacyEnvelope(signatureData) {
            return try verifyLegacy(manifestData: manifestData, signatureData: signatureData)
        }

        let envelope = try ManifestSignature.decode(signatureData)
        guard envelope.signatureVersion == 1 else {
            throw ManifestVerificationError.unsupportedSignatureVersion(envelope.signatureVersion)
        }
        guard envelope.signatureType == Self.signatureType else {
            throw ManifestVerificationError.unsupportedSignatureType(envelope.signatureType)
        }
        guard envelope.algorithm == Self.algorithm else {
            throw ManifestVerificationError.unsupportedAlgorithm(envelope.algorithm)
        }
        let publicKey = try trustedPublicKey(for: envelope.keyId)
        guard envelope.manifestFile == Self.manifestFile else {
            throw ManifestVerificationError.unexpectedManifestFile(envelope.manifestFile)
        }
        guard let contentTypeVersion = Self.manifestVersion(
            fromContentType: envelope.contentType
        ) else {
            throw ManifestVerificationError.unsupportedContentType(envelope.contentType)
        }

        let contentSHA256 = Self.sha256Hex(manifestData)
        guard envelope.contentSHA256 == contentSHA256 else {
            throw ManifestVerificationError.contentHashMismatch
        }
        guard let signatureBytes = Self.decodeBase64URLNoPadding(envelope.signature) else {
            throw ManifestVerificationError.invalidSignatureEncoding
        }

        let payload = Self.canonicalPayload(
            signatureVersion: envelope.signatureVersion,
            signatureType: envelope.signatureType,
            algorithm: envelope.algorithm,
            keyId: envelope.keyId,
            manifestFile: envelope.manifestFile,
            contentType: envelope.contentType,
            contentSHA256: envelope.contentSHA256
        )
        guard publicKey.isValidSignature(signatureBytes, for: payload) else {
            throw ManifestVerificationError.signatureRejected
        }
        let bodyVersion = try Self.manifestVersion(in: manifestData)
        guard bodyVersion == contentTypeVersion else {
            throw ManifestVerificationError.contentTypeManifestVersionMismatch
        }
        guard let envelopeVersion = ModelManifestSchemaVersion(
            rawValue: contentTypeVersion
        ) else {
            throw ManifestVerificationError.unsupportedManifestVersion(
                contentTypeVersion
            )
        }
        let manifest: ModelManifest
        do {
            manifest = try ModelManifest.decode(manifestData)
        } catch let error as ModelManifestDecodingError {
            switch error {
            case let .unsupportedManifestVersion(version):
                throw ManifestVerificationError.unsupportedManifestVersion(version)
            }
        }
        guard envelopeVersion.rawValue == manifest.manifestVersion else {
            throw ManifestVerificationError.contentTypeManifestVersionMismatch
        }
        return manifest
    }

    private func verifyLegacy(manifestData: Data, signatureData: Data) throws -> ModelManifest {
        let signature = try JSONDecoder().decode(LegacyManifestSignature.self, from: signatureData)
        guard let legacyPolicy,
              signature.keyId == legacyPolicy.keyId,
              Self.sha256Hex(manifestData) == legacyPolicy.contentSHA256
        else {
            throw ManifestVerificationError.legacyEnvelopeRejected
        }
        guard signature.signatureVersion == 1 else {
            throw ManifestVerificationError.unsupportedSignatureVersion(signature.signatureVersion)
        }
        guard signature.algorithm == Self.algorithm else {
            throw ManifestVerificationError.unsupportedAlgorithm(signature.algorithm)
        }
        let publicKey = try trustedPublicKey(for: signature.keyId)
        guard let signatureBytes = Data(base64Encoded: signature.signatureBase64) else {
            throw ManifestVerificationError.invalidSignatureEncoding
        }
        guard publicKey.isValidSignature(signatureBytes, for: manifestData) else {
            throw ManifestVerificationError.signatureRejected
        }
        return try ModelManifest.decode(manifestData)
    }

    private func trustedPublicKey(for keyId: String) throws -> Curve25519.Signing.PublicKey {
        guard let trustedKey = trustedKeys.first(where: { $0.keyId == keyId }) else {
            throw ManifestVerificationError.unknownKeyId(keyId)
        }
        guard let publicKeyData = Data(base64Encoded: trustedKey.publicKeyBase64) else {
            throw ManifestVerificationError.invalidSignatureEncoding
        }
        do {
            return try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        } catch {
            throw ManifestVerificationError.invalidPublicKey
        }
    }

    private func isLegacyEnvelope(_ signatureData: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: signatureData)
            as? [String: Any] else {
            return false
        }
        return object["signatureBase64"] != nil
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func canonicalPayload(
        signatureVersion: Int,
        signatureType: String,
        algorithm: String,
        keyId: String,
        manifestFile: String,
        contentType: String,
        contentSHA256: String
    ) -> Data {
        Data("""
        TEXTIFY-MODEL-MANIFEST-SIGNATURE-V1
        signatureVersion=\(signatureVersion)
        signatureType=\(signatureType)
        algorithm=\(algorithm)
        keyId=\(keyId)
        manifestFile=\(manifestFile)
        contentType=\(contentType)
        contentSHA256=\(contentSHA256)

        """.utf8)
    }

    private static func decodeBase64URLNoPadding(_ value: String) -> Data? {
        guard !value.isEmpty,
              !value.contains("="),
              value.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
              })
        else {
            return nil
        }

        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))
        return Data(base64Encoded: base64)
    }

    private static func manifestVersion(fromContentType contentType: String) -> Int? {
        let prefix = "application/vnd.textify.model-manifest+json;version="
        guard contentType.hasPrefix(prefix) else {
            return nil
        }
        let suffix = contentType.dropFirst(prefix.count)
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else {
            return nil
        }
        return Int(suffix)
    }

    private static func manifestVersion(in manifestData: Data) throws -> Int {
        try JSONDecoder().decode(
            ManifestVersionEnvelope.self,
            from: manifestData
        ).manifestVersion
    }
}

private struct ManifestVersionEnvelope: Decodable {
    let manifestVersion: Int
}

private struct LegacyManifestSignature: Decodable {
    let signatureVersion: Int
    let keyId: String
    let algorithm: String
    let signatureBase64: String

    init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        signatureVersion = try container.decode(Int.self, forKey: .signatureVersion)
        keyId = try container.decode(String.self, forKey: .keyId)
        algorithm = try container.decode(String.self, forKey: .algorithm)
        signatureBase64 = try container.decode(String.self, forKey: .signatureBase64)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case signatureVersion
        case keyId
        case algorithm
        case signatureBase64
    }
}
