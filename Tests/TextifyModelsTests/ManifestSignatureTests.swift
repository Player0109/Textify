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

    func testVerifierAcceptsSignatureOverExactManifestBytes() throws {
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

        let manifest = try verifier.verify(manifestData: manifestData, signatureData: signatureData)

        XCTAssertEqual(manifest.manifestVersion, 1)
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
        let verifier = ManifestVerifier(trustedKeys: [
            TrustedModelManifestKey(
                keyId: "test-key",
                publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
            )
        ])

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
        let verifier = ManifestVerifier(trustedKeys: [
            TrustedModelManifestKey(
                keyId: "test-key",
                publicKeyBase64: " \(privateKey.publicKey.rawRepresentation.base64EncodedString()) "
            )
        ])

        XCTAssertThrowsError(try verifier.verify(manifestData: manifestData, signatureData: signatureData)) { error in
            XCTAssertEqual(error as? ManifestVerificationError, .invalidSignatureEncoding)
        }
    }

    func testVerifierAcceptsFixtureSignature() throws {
        let verifier = ManifestVerifier(trustedKeys: [
            TrustedModelManifestKey(
                keyId: "fixture-key",
                publicKeyBase64: try Self.fixtureString("manifest.fixture-public-key.base64")
            )
        ])

        let manifest = try verifier.verify(
            manifestData: try Self.fixtureData("manifest.json"),
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
