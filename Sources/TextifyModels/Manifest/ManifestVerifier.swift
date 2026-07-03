import CryptoKit
import Foundation

public enum ManifestVerificationError: Error, Equatable {
    case unsupportedSignatureVersion(Int)
    case unsupportedAlgorithm(String)
    case unknownKeyId(String)
    case invalidPublicKey
    case invalidSignatureEncoding
    case signatureRejected
}

public struct TrustedModelManifestKey: Equatable, Sendable {
    public let keyId: String
    public let publicKeyBase64: String

    public init(keyId: String, publicKeyBase64: String) {
        self.keyId = keyId
        self.publicKeyBase64 = publicKeyBase64
    }
}

public struct ManifestVerifier {
    public static let algorithm = "Ed25519"
    private let trustedKeys: [TrustedModelManifestKey]

    public init(trustedKeys: [TrustedModelManifestKey]) {
        self.trustedKeys = trustedKeys
    }

    public func verify(manifestData: Data, signatureData: Data) throws -> ModelManifest {
        let signature = try ManifestSignature.decode(signatureData)
        guard signature.signatureVersion == 1 else {
            throw ManifestVerificationError.unsupportedSignatureVersion(signature.signatureVersion)
        }
        guard signature.algorithm == Self.algorithm else {
            throw ManifestVerificationError.unsupportedAlgorithm(signature.algorithm)
        }
        guard let trustedKey = trustedKeys.first(where: { $0.keyId == signature.keyId }) else {
            throw ManifestVerificationError.unknownKeyId(signature.keyId)
        }
        guard let publicKeyData = Data(base64Encoded: trustedKey.publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
              let signatureBytes = Data(base64Encoded: signature.signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            throw ManifestVerificationError.invalidSignatureEncoding
        }

        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        } catch {
            throw ManifestVerificationError.invalidPublicKey
        }

        guard publicKey.isValidSignature(signatureBytes, for: manifestData) else {
            throw ManifestVerificationError.signatureRejected
        }
        return try ModelManifest.decode(manifestData)
    }
}
