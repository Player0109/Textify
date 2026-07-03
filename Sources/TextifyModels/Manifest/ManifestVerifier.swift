import CryptoKit
import Foundation

public enum ManifestVerificationError: Error, Equatable {
    case unsupportedSignatureVersion(Int)
    case unsupportedSignatureType(String)
    case unsupportedAlgorithm(String)
    case unknownKeyId(String)
    case unexpectedManifestFile(String)
    case unexpectedContentType(String)
    case contentHashMismatch(expected: String, actual: String)
    case invalidPublicKey
    case invalidSignatureEncoding
    case signatureRejected
}

public struct ManifestVerifier {
    public static let signatureType = "io.github.Player0109.Textify.model-manifest"
    public static let algorithm = "Ed25519"
    public static let keyId = "model-manifest-v1"
    public static let manifestFile = "manifest.json"
    public static let contentType = "application/vnd.textify.model-manifest+json;version=1"

    public init() {}

    public func canonicalPayload(signature: ManifestSignature) -> Data {
        let lines = [
            "TEXTIFY-MODEL-MANIFEST-SIGNATURE-V1",
            "signatureVersion=\(signature.signatureVersion)",
            "signatureType=\(signature.signatureType)",
            "algorithm=\(signature.algorithm)",
            "keyId=\(signature.keyId)",
            "manifestFile=\(signature.manifestFile)",
            "contentType=\(signature.contentType)",
            "contentSHA256=\(signature.contentSHA256)"
        ]
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    public func verify(
        manifestData: Data,
        signatureData: Data,
        publicKeyBase64: String
    ) throws {
        let signature = try ManifestSignature.decode(signatureData)
        try validateSignatureMetadata(signature)

        let actualHash = SHA256.textifyHexDigest(for: manifestData)
        guard actualHash == signature.contentSHA256 else {
            throw ManifestVerificationError.contentHashMismatch(
                expected: signature.contentSHA256,
                actual: actualHash
            )
        }

        guard let publicKeyData = Data(
            base64Encoded: publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        ) else {
            throw ManifestVerificationError.invalidPublicKey
        }

        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        } catch {
            throw ManifestVerificationError.invalidPublicKey
        }

        guard let signatureBytes = Data(textifyBase64URLEncoded: signature.signature) else {
            throw ManifestVerificationError.invalidSignatureEncoding
        }

        guard publicKey.isValidSignature(signatureBytes, for: canonicalPayload(signature: signature)) else {
            throw ManifestVerificationError.signatureRejected
        }

        _ = try ModelManifest.decode(manifestData)
    }

    private func validateSignatureMetadata(_ signature: ManifestSignature) throws {
        guard signature.signatureVersion == 1 else {
            throw ManifestVerificationError.unsupportedSignatureVersion(signature.signatureVersion)
        }
        guard signature.signatureType == Self.signatureType else {
            throw ManifestVerificationError.unsupportedSignatureType(signature.signatureType)
        }
        guard signature.algorithm == Self.algorithm else {
            throw ManifestVerificationError.unsupportedAlgorithm(signature.algorithm)
        }
        guard signature.keyId == Self.keyId else {
            throw ManifestVerificationError.unknownKeyId(signature.keyId)
        }
        guard signature.manifestFile == Self.manifestFile else {
            throw ManifestVerificationError.unexpectedManifestFile(signature.manifestFile)
        }
        guard signature.contentType == Self.contentType else {
            throw ManifestVerificationError.unexpectedContentType(signature.contentType)
        }
    }
}

private extension SHA256 {
    static func textifyHexDigest(for data: Data) -> String {
        hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension Data {
    init?(textifyBase64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = base64.count % 4
        if padding > 0 {
            base64.append(String(repeating: "=", count: 4 - padding))
        }

        self.init(base64Encoded: base64)
    }
}
