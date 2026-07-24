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
        keyID: String = "revocation-test-key",
        version: Int = 1,
        restorations: [ModelRestorationRecord] = []
    ) throws -> TrustedModelRevocationSnapshot {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let revocationData = try encoder.encode(
            ModelRevocationEnvelope(
                revocationVersion: version,
                generatedAt: revision,
                records: records,
                restorations: restorations
            )
        )
        let contentSHA256 = SHA256.hash(data: revocationData)
            .map { String(format: "%02x", $0) }
            .joined()
        let contentType = version == 1
            ? ModelRevocationVerifier.contentTypeV1
            : ModelRevocationVerifier.contentTypeV2
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

    static func restoredState(
        record: ModelRevocationRecord,
        restoration: ModelRestorationRecord
    ) throws -> TrustedModelRevocationState {
        let privateKey = Curve25519.Signing.PrivateKey()
        return try TrustedModelRevocationState(
            snapshots: [
                snapshot(
                    revision: "2026-07-24T01:00:00Z",
                    records: [record],
                    privateKey: privateKey
                ),
                snapshot(
                    revision: "2026-07-24T02:00:00Z",
                    records: [],
                    privateKey: privateKey,
                    version: 2,
                    restorations: [restoration]
                ),
            ]
        )
    }
}
