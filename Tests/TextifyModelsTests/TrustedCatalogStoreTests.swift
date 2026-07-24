import TextifyModels
import XCTest

final class TrustedCatalogStoreTests: XCTestCase {
    func testRoundTripsVerifiedPresentedAndStagedSnapshotsWithIndependentRevisions() throws {
        let fixture = try signedV3Fixture()
        let snapshot = try TrustedCatalogSnapshot(
            manifestData: fixture.manifestData,
            signatureData: fixture.signatureData,
            verifier: fixture.verifier
        )
        let issue = TrustedCatalogSecurityIssue(
            reason: .schemaValidation,
            candidateRevision: "2026-07-25T00:00:00Z",
            highestAcceptedRevision: snapshot.revision
        )
        let state = TrustedCatalogStoredState(
            highestAcceptedRevision: snapshot.revision,
            presentedSnapshot: snapshot,
            stagedSnapshot: nil,
            securityIssue: issue
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrustedCatalogStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrustedCatalogStore(
            fileURL: directory.appendingPathComponent("catalog-state.json"),
            verifier: fixture.verifier
        )

        try store.save(state)
        let restored = try store.load()

        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.presentedSnapshot?.manifest.manifestVersion, 3)
        XCTAssertEqual(restored.securityIssue?.severity, .high)
    }

    func testRejectsCacheWhoseSignedManifestBytesWereTamperedAfterPersistence() throws {
        let fixture = try signedV3Fixture()
        let snapshot = try TrustedCatalogSnapshot(
            manifestData: fixture.manifestData,
            signatureData: fixture.signatureData,
            verifier: fixture.verifier
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrustedCatalogStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("catalog-state.json")
        let store = TrustedCatalogStore(fileURL: fileURL, verifier: fixture.verifier)
        try store.save(
            TrustedCatalogStoredState(
                highestAcceptedRevision: snapshot.revision,
                presentedSnapshot: snapshot
            )
        )
        var archive = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fileURL))
                as? [String: Any]
        )
        var presented = try XCTUnwrap(archive["presentedSnapshot"] as? [String: Any])
        presented["manifestData"] = Data("tampered".utf8).base64EncodedString()
        archive["presentedSnapshot"] = presented
        try JSONSerialization.data(
            withJSONObject: archive,
            options: [.sortedKeys]
        ).write(to: fileURL, options: .atomic)

        XCTAssertThrowsError(try store.load())
    }

    func testRejectsAcceptedRevisionWithoutMatchingPresentedOrStagedSnapshot() throws {
        let fixture = try signedV3Fixture()
        let snapshot = try TrustedCatalogSnapshot(
            manifestData: fixture.manifestData,
            signatureData: fixture.signatureData,
            verifier: fixture.verifier
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrustedCatalogStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TrustedCatalogStore(
            fileURL: directory.appendingPathComponent("catalog-state.json"),
            verifier: fixture.verifier
        )

        XCTAssertThrowsError(
            try store.save(
                TrustedCatalogStoredState(
                    highestAcceptedRevision: "2026-07-25T00:00:00Z",
                    presentedSnapshot: snapshot
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? TrustedCatalogStoreError,
                .invalidRevisionOrder
            )
        }
    }

    private func signedV3Fixture() throws -> (
        manifestData: Data,
        signatureData: Data,
        verifier: ManifestVerifier
    ) {
        let manifestData = try fixtureData("manifest_v3.json")
        let signatureData = try fixtureData("manifest_v3.json.sig")
        let publicKey = String(
            decoding: try fixtureData("manifest_v3.fixture-public-key.base64"),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            manifestData,
            signatureData,
            ManifestVerifier(
                trustedKeys: [
                    TrustedModelManifestKey(
                        keyId: "fixture-v3-key",
                        publicKeyBase64: publicKey
                    ),
                ]
            )
        )
    }

    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: nil,
                subdirectory: "Fixtures/Models"
            )
        )
        return try Data(contentsOf: url)
    }
}
