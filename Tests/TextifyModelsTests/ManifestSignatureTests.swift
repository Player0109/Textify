import CryptoKit
import TextifyModels
import XCTest

final class ManifestSignatureTests: XCTestCase {
    private static func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: nil,
                subdirectory: "Fixtures/Models"
            )
        )
        return try Data(contentsOf: url)
    }

    private static func fixtureString(_ name: String) throws -> String {
        String(decoding: try fixtureData(name), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func legacyPolicy(
        manifestData: Data,
        keyId: String = "test-key"
    ) -> LegacyManifestSignaturePolicy {
        LegacyManifestSignaturePolicy(
            keyId: keyId,
            contentSHA256: SHA256.hash(data: manifestData)
                .map { String(format: "%02x", $0) }
                .joined()
        )
    }

    private static func specEnvelope(
        manifestData: Data,
        privateKey: Curve25519.Signing.PrivateKey,
        keyId: String = "test-key",
        contentTypeVersion: Int = 1
    ) throws -> Data {
        let contentSHA256 = SHA256.hash(data: manifestData)
            .map { String(format: "%02x", $0) }
            .joined()
        let canonicalPayload = Data("""
        TEXTIFY-MODEL-MANIFEST-SIGNATURE-V1
        signatureVersion=1
        signatureType=io.github.Player0109.Textify.model-manifest
        algorithm=Ed25519
        keyId=\(keyId)
        manifestFile=manifest.json
        contentType=application/vnd.textify.model-manifest+json;version=\(contentTypeVersion)
        contentSHA256=\(contentSHA256)

        """.utf8)
        let signature = try privateKey.signature(for: canonicalPayload)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return Data("""
        {
          "signatureVersion": 1,
          "signatureType": "io.github.Player0109.Textify.model-manifest",
          "algorithm": "Ed25519",
          "keyId": "\(keyId)",
          "manifestFile": "manifest.json",
          "contentType": "application/vnd.textify.model-manifest+json;version=\(contentTypeVersion)",
          "contentSHA256": "\(contentSHA256)",
          "signature": "\(signature)"
        }
        """.utf8)
    }

    func testVerifierAcceptsSpecCanonicalEnvelope() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let manifestData = Data(#"{"manifestVersion":1,"generatedAt":"2026-07-03T00:00:00Z","models":[]}"#.utf8)
        let verifier = ManifestVerifier(
            trustedKeys: [
                TrustedModelManifestKey(
                    keyId: "test-key",
                    publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
                )
            ],
            legacyPolicy: Self.legacyPolicy(manifestData: manifestData)
        )

        let manifest = try verifier.verify(
            manifestData: manifestData,
            signatureData: Self.specEnvelope(manifestData: manifestData, privateKey: privateKey)
        )

        XCTAssertEqual(manifest.manifestVersion, 1)
    }

    func testVerifierAcceptsManifestV2ContentType() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let manifestData = Data(
            #"{"manifestVersion":2,"generatedAt":"2026-07-22T00:00:00Z","models":[]}"#.utf8
        )
        let verifier = ManifestVerifier(trustedKeys: [
            TrustedModelManifestKey(
                keyId: "test-key",
                publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
            )
        ])

        let manifest = try verifier.verify(
            manifestData: manifestData,
            signatureData: Self.specEnvelope(
                manifestData: manifestData,
                privateKey: privateKey,
                contentTypeVersion: 2
            )
        )

        XCTAssertEqual(manifest.manifestVersion, 2)
    }

    func testVerifierClassifiesAuthenticFutureSchemaAsUnsupportedVersion() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let manifestData = Data(
            #"{"manifestVersion":4,"generatedAt":"2026-07-25T00:00:00Z","models":[]}"#.utf8
        )
        let verifier = ManifestVerifier(trustedKeys: [
            TrustedModelManifestKey(
                keyId: "test-key",
                publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
            ),
        ])

        XCTAssertThrowsError(
            try verifier.verify(
                manifestData: manifestData,
                signatureData: Self.specEnvelope(
                    manifestData: manifestData,
                    privateKey: privateKey,
                    contentTypeVersion: 4
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ManifestVerificationError,
                .unsupportedManifestVersion(4)
            )
        }
    }

    func testVerifierSurfacesAuthenticMalformedJSONAsStrictDecodeFailure() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let manifestData = Data(#"{"manifestVersion":3"#.utf8)
        let verifier = ManifestVerifier(trustedKeys: [
            TrustedModelManifestKey(
                keyId: "test-key",
                publicKeyBase64: privateKey.publicKey.rawRepresentation
                    .base64EncodedString()
            ),
        ])

        XCTAssertThrowsError(
            try verifier.verify(
                manifestData: manifestData,
                signatureData: Self.specEnvelope(
                    manifestData: manifestData,
                    privateKey: privateKey,
                    contentTypeVersion: 3
                )
            )
        ) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testVerifierRejectsContentTypeVersionDifferentFromManifest() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let manifestData = Data(
            #"{"manifestVersion":2,"generatedAt":"2026-07-22T00:00:00Z","models":[]}"#.utf8
        )
        let verifier = ManifestVerifier(trustedKeys: [
            TrustedModelManifestKey(
                keyId: "test-key",
                publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
            )
        ])

        XCTAssertThrowsError(
            try verifier.verify(
                manifestData: manifestData,
                signatureData: Self.specEnvelope(
                    manifestData: manifestData,
                    privateKey: privateKey,
                    contentTypeVersion: 1
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ManifestVerificationError,
                .contentTypeManifestVersionMismatch
            )
        }
    }

    func testVerifierRejectsSpecEnvelopeWhenManifestHashChanges() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let manifestData = Data(#"{"manifestVersion":1,"generatedAt":"2026-07-03T00:00:00Z","models":[]}"#.utf8)
        var changedManifestData = manifestData
        changedManifestData.append(0x0a)
        let verifier = ManifestVerifier(trustedKeys: [
            TrustedModelManifestKey(
                keyId: "test-key",
                publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
            )
        ])

        XCTAssertThrowsError(
            try verifier.verify(
                manifestData: changedManifestData,
                signatureData: Self.specEnvelope(manifestData: manifestData, privateKey: privateKey)
            )
        ) { error in
            XCTAssertEqual(error as? ManifestVerificationError, .contentHashMismatch)
        }
    }

    func testVerifierAcceptsOnlyExplicitlyPinnedLegacyManifestBytes() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let manifestData = Data(#"{"manifestVersion":1,"generatedAt":"2026-07-03T00:00:00Z","models":[]}"#.utf8)
        let signature = try privateKey.signature(for: manifestData).base64EncodedString()
        let signatureData = Data("""
        {"signatureVersion":1,"keyId":"test-key","algorithm":"Ed25519","signatureBase64":"\(signature)"}
        """.utf8)

        let verifier = ManifestVerifier(
            trustedKeys: [
                TrustedModelManifestKey(
                    keyId: "test-key",
                    publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
                )
            ],
            legacyPolicy: LegacyManifestSignaturePolicy(
                keyId: "test-key",
                contentSHA256: SHA256.hash(data: manifestData)
                    .map { String(format: "%02x", $0) }
                    .joined()
            )
        )

        let manifest = try verifier.verify(manifestData: manifestData, signatureData: signatureData)

        XCTAssertEqual(manifest.manifestVersion, 1)
    }

    func testVerifierRejectsLegacyEnvelopeWithoutPinnedMigrationPolicy() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let manifestData = Data(#"{"manifestVersion":1,"generatedAt":"2026-07-03T00:00:00Z","models":[]}"#.utf8)
        let signature = try privateKey.signature(for: manifestData).base64EncodedString()
        let signatureData = Data("""
        {"signatureVersion":1,"keyId":"test-key","algorithm":"Ed25519","signatureBase64":"\(signature)"}
        """.utf8)
        let verifier = ManifestVerifier(trustedKeys: [
            TrustedModelManifestKey(
                keyId: "test-key",
                publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
            )
        ])

        XCTAssertThrowsError(
            try verifier.verify(manifestData: manifestData, signatureData: signatureData)
        ) { error in
            XCTAssertEqual(error as? ManifestVerificationError, .legacyEnvelopeRejected)
        }
    }

    func testVerifierRejectsWhitespaceChangedAfterSigning() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let signedData = Data(#"{"manifestVersion":1,"generatedAt":"2026-07-03T00:00:00Z","models":[]}"#.utf8)
        let changedData = Data(#"{ "manifestVersion": 1, "generatedAt": "2026-07-03T00:00:00Z", "models": [] }"#.utf8)
        let signature = try privateKey.signature(for: signedData).base64EncodedString()
        let signatureData = Data("""
        {"signatureVersion":1,"keyId":"test-key","algorithm":"Ed25519","signatureBase64":"\(signature)"}
        """.utf8)
        let verifier = ManifestVerifier(trustedKeys: [
            TrustedModelManifestKey(
                keyId: "test-key",
                publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
            )
        ])

        XCTAssertThrowsError(try verifier.verify(manifestData: changedData, signatureData: signatureData))
    }

    func testVerifierRejectsSignatureBase64WithLeadingTrailingWhitespace() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let manifestData = Data(#"{"manifestVersion":1,"generatedAt":"2026-07-03T00:00:00Z","models":[]}"#.utf8)
        let signature = try privateKey.signature(for: manifestData).base64EncodedString()
        let signatureData = Data("""
        {"signatureVersion":1,"keyId":"test-key","algorithm":"Ed25519","signatureBase64":" \(signature) "}
        """.utf8)
        let verifier = ManifestVerifier(
            trustedKeys: [
                TrustedModelManifestKey(
                    keyId: "test-key",
                    publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
                )
            ],
            legacyPolicy: Self.legacyPolicy(manifestData: manifestData)
        )

        XCTAssertThrowsError(try verifier.verify(manifestData: manifestData, signatureData: signatureData)) { error in
            XCTAssertEqual(error as? ManifestVerificationError, .invalidSignatureEncoding)
        }
    }

    func testVerifierRejectsPublicKeyBase64WithLeadingTrailingWhitespace() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let manifestData = Data(#"{"manifestVersion":1,"generatedAt":"2026-07-03T00:00:00Z","models":[]}"#.utf8)
        let signature = try privateKey.signature(for: manifestData).base64EncodedString()
        let signatureData = Data("""
        {"signatureVersion":1,"keyId":"test-key","algorithm":"Ed25519","signatureBase64":"\(signature)"}
        """.utf8)
        let verifier = ManifestVerifier(
            trustedKeys: [
                TrustedModelManifestKey(
                    keyId: "test-key",
                    publicKeyBase64: " \(privateKey.publicKey.rawRepresentation.base64EncodedString()) "
                )
            ],
            legacyPolicy: Self.legacyPolicy(manifestData: manifestData)
        )

        XCTAssertThrowsError(try verifier.verify(manifestData: manifestData, signatureData: signatureData)) { error in
            XCTAssertEqual(error as? ManifestVerificationError, .invalidSignatureEncoding)
        }
    }

    func testSignatureUnknownFieldsAreRejected() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let manifestData = Data(#"{"manifestVersion":1,"generatedAt":"2026-07-03T00:00:00Z","models":[]}"#.utf8)
        let signatureJSON = String(
            decoding: try Self.specEnvelope(manifestData: manifestData, privateKey: privateKey),
            as: UTF8.self
        )
        let data = Data(signatureJSON.replacingOccurrences(
            of: "\n}",
            with: ",\n  \"unexpectedFieldForStrictSchemaTest\": true\n}"
        ).utf8)

        XCTAssertThrowsError(try ManifestSignature.decode(data))
    }

    func testVerifierAcceptsFixtureSignature() throws {
        let manifestData = try Self.fixtureData("manifest.json")
        let verifier = ManifestVerifier(
            trustedKeys: [
                TrustedModelManifestKey(
                    keyId: "fixture-key",
                    publicKeyBase64: try Self.fixtureString("manifest.fixture-public-key.base64")
                )
            ],
            legacyPolicy: LegacyManifestSignaturePolicy(
                keyId: "fixture-key",
                contentSHA256: SHA256.hash(data: manifestData)
                    .map { String(format: "%02x", $0) }
                    .joined()
            )
        )

        let manifest = try verifier.verify(
            manifestData: manifestData,
            signatureData: try Self.fixtureData("manifest.json.sig")
        )

        XCTAssertEqual(manifest.models.first?.id, ProductionModelPolicy.requiredModelID)
    }

    func testVerifierRejectsTamperedManifestBytes() throws {
        var manifestData = try Self.fixtureData("manifest.json")
        manifestData.append(Data("\n".utf8))
        let verifier = ManifestVerifier(trustedKeys: [
            TrustedModelManifestKey(
                keyId: "fixture-key",
                publicKeyBase64: try Self.fixtureString("manifest.fixture-public-key.base64")
            )
        ])

        XCTAssertThrowsError(
            try verifier.verify(
                manifestData: manifestData,
                signatureData: try Self.fixtureData("manifest.json.sig")
            )
        )
    }
}
