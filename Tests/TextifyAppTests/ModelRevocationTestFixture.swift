import CryptoKit
import Foundation
import TextifyModels

enum ModelRevocationTestFixture {
    static func state(
        revision: String = "2026-07-24T01:00:00Z",
        records: [ModelRevocationRecord]
    ) throws -> TrustedModelRevocationState {
        let privateKey = Curve25519.Signing.PrivateKey()
        return try TrustedModelRevocationState(
            snapshots: [
                snapshot(
                    revision: revision,
                    records: records,
                    privateKey: privateKey
                ),
            ]
        )
    }

    static func snapshot(
        revision: String,
        records: [ModelRevocationRecord],
        privateKey: Curve25519.Signing.PrivateKey,
        keyID: String = "revocation-test-key"
    ) throws -> TrustedModelRevocationSnapshot {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let revocationData = try encoder.encode(
            ModelRevocationEnvelope(
                revocationVersion: 1,
                generatedAt: revision,
                records: records
            )
        )
        let contentSHA256 = SHA256.hash(data: revocationData)
            .map { String(format: "%02x", $0) }
            .joined()
        let contentType = ModelRevocationVerifier.contentTypeV1
        let payload = Data(
            """
            TEXTIFY-MODEL-REVOCATIONS-SIGNATURE-V1
            signatureVersion=1
            signatureType=io.github.Player0109.Textify.model-revocations
            algorithm=Ed25519
            keyId=\(keyID)
            revocationFile=revocations.json
            contentType=\(contentType)
            contentSHA256=\(contentSHA256)

            """.utf8
        )
        let signature = try privateKey.signature(for: payload)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let signatureData = Data(
            """
            {
              "signatureVersion": 1,
              "signatureType": "io.github.Player0109.Textify.model-revocations",
              "algorithm": "Ed25519",
              "keyId": "\(keyID)",
              "revocationFile": "revocations.json",
              "contentType": "\(contentType)",
              "contentSHA256": "\(contentSHA256)",
              "signature": "\(signature)"
            }
            """.utf8
        )
        return try TrustedModelRevocationSnapshot(
            revocationData: revocationData,
            signatureData: signatureData,
            verifier: ModelRevocationVerifier(
                trustedKeys: [
                    TrustedModelManifestKey(
                        keyId: keyID,
                        publicKeyBase64: privateKey.publicKey.rawRepresentation
                            .base64EncodedString()
                    ),
                ]
            )
        )
    }
}
