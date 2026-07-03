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

    func testSignatureEnvelopeParsesAndBuildsCanonicalPayload() throws {
        let signature = try ManifestSignature.decode(try Self.fixtureData("manifest.json.sig"))
        let payload = String(
            decoding: ManifestVerifier().canonicalPayload(signature: signature),
            as: UTF8.self
        )

        XCTAssertEqual(signature.signatureVersion, 1)
        XCTAssertEqual(signature.signatureType, "io.github.Player0109.Textify.model-manifest")
        XCTAssertEqual(signature.algorithm, "Ed25519")
        XCTAssertEqual(signature.keyId, "model-manifest-v1")
        XCTAssertTrue(payload.hasSuffix("\n"))
        XCTAssertTrue(payload.contains("contentSHA256=\(signature.contentSHA256)\n"))
    }

    func testVerifierAcceptsValidFixtureSignature() throws {
        try ManifestVerifier().verify(
            manifestData: try Self.fixtureData("manifest.json"),
            signatureData: try Self.fixtureData("manifest.json.sig"),
            publicKeyBase64: try Self.fixtureString("manifest.fixture-public-key.base64")
        )
    }

    func testVerifierRejectsTamperedManifestBytes() throws {
        var manifestData = try Self.fixtureData("manifest.json")
        manifestData.append(Data("\n".utf8))

        XCTAssertThrowsError(
            try ManifestVerifier().verify(
                manifestData: manifestData,
                signatureData: try Self.fixtureData("manifest.json.sig"),
                publicKeyBase64: try Self.fixtureString("manifest.fixture-public-key.base64")
            )
        )
    }

    func testSignatureUnknownFieldsAreRejected() throws {
        let signatureJSON = String(decoding: try Self.fixtureData("manifest.json.sig"), as: UTF8.self)
        let data = Data(signatureJSON.replacingOccurrences(
            of: "\n}",
            with: ",\n  \"unexpectedFieldForStrictSchemaTest\": true\n}"
        ).utf8)

        XCTAssertThrowsError(try ManifestSignature.decode(data))
    }
}
