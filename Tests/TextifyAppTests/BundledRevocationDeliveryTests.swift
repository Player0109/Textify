import CryptoKit
import XCTest
@testable import Textify
import TextifyModels

final class BundledRevocationDeliveryTests: XCTestCase {
    func testBundledRevocationPairIsRequiredAndComplete() throws {
        let resources = try Self.makeResourceDirectory()
        defer { try? FileManager.default.removeItem(at: resources) }
        let loader = ProductionModelManifestLoader(
            configuration: ProductionModelInstallConfiguration(
                trustedKeys: ProductionModelCatalogTrust.trustedKeys
            ),
            resourceDirectory: resources
        )

        XCTAssertThrowsError(try loader.loadBundledRevocationSnapshot()) {
            XCTAssertEqual(
                $0 as? ProductionModelManifestLoaderError,
                .bundledRevocationMissing
            )
        }

        try Data("{}".utf8).write(
            to: Self.catalogDirectory(in: resources)
                .appendingPathComponent(
                    ProductionModelManifestLoader.bundledRevocationName
                )
        )

        XCTAssertThrowsError(try loader.loadBundledRevocationSnapshot()) {
            XCTAssertEqual(
                $0 as? ProductionModelManifestLoaderError,
                .bundledRevocationIncomplete
            )
        }
    }

    func testBundledTrustMergesAndPersistsStickyRevocations() throws {
        let resources = try Self.makeResourceDirectory()
        defer { try? FileManager.default.removeItem(at: resources) }
        try Self.copyProductionCatalog(to: resources)
        let privateKey = Curve25519.Signing.PrivateKey()
        let persistedSnapshot = try ModelRevocationTestFixture.snapshot(
            revision: "2026-07-30T00:00:00Z",
            records: [
                ModelRevocationRecord(
                    recordID: "persisted-revocation",
                    exactArtifactID: "persisted-artifact"
                ),
            ],
            privateKey: privateKey
        )
        let bundledSnapshot = try ModelRevocationTestFixture.snapshot(
            revision: "2026-07-31T00:00:00Z",
            records: [
                ModelRevocationRecord(
                    recordID: "bundled-revocation",
                    exactArtifactID: "bundled-artifact"
                ),
            ],
            privateKey: privateKey
        )
        try Self.write(bundledSnapshot, to: resources)
        let persistedState = try TrustedModelRevocationState(
            snapshots: [persistedSnapshot]
        )
        var savedState: TrustedModelRevocationState?

        let trust = try Self.loader(
            resources: resources,
            privateKey: privateKey
        ).loadBundledTrust(
            persistedRevocationState: persistedState
        ) {
            savedState = $0
        }

        XCTAssertEqual(
            Set(trust.revocationState.overlay.records.map(\.recordID)),
            ["persisted-revocation", "bundled-revocation"]
        )
        XCTAssertEqual(savedState, trust.revocationState)
        XCTAssertEqual(
            trust.catalogSnapshot.manifest.manifestVersion,
            3
        )
    }

    func testBundledTrustFailsClosedWhenStickyStateCannotPersist() throws {
        let resources = try Self.makeResourceDirectory()
        defer { try? FileManager.default.removeItem(at: resources) }
        try Self.copyProductionCatalog(to: resources)
        let privateKey = Curve25519.Signing.PrivateKey()
        try Self.write(
            ModelRevocationTestFixture.snapshot(
                revision: "2026-07-31T00:00:00Z",
                records: [],
                privateKey: privateKey
            ),
            to: resources
        )

        XCTAssertThrowsError(
            try Self.loader(
                resources: resources,
                privateKey: privateKey
            ).loadBundledTrust(
                persistedRevocationState: TrustedModelRevocationState()
            ) { _ in
                throw FixtureError.persistenceUnavailable
            }
        ) {
            XCTAssertEqual(
                $0 as? FixtureError,
                .persistenceUnavailable
            )
        }
    }

    func testBundledTrustRejectsTamperedRevocationBytesWithoutSaving() throws {
        let resources = try Self.makeResourceDirectory()
        defer { try? FileManager.default.removeItem(at: resources) }
        try Self.copyProductionCatalog(to: resources)
        let privateKey = Curve25519.Signing.PrivateKey()
        let snapshot = try ModelRevocationTestFixture.snapshot(
            revision: "2026-07-31T00:00:00Z",
            records: [],
            privateKey: privateKey
        )
        try Self.write(snapshot, to: resources)
        let revocationURL = Self.catalogDirectory(in: resources)
            .appendingPathComponent(
                ProductionModelManifestLoader.bundledRevocationName
            )
        var tamperedData = try Data(contentsOf: revocationURL)
        tamperedData.append(0x0A)
        try tamperedData.write(to: revocationURL)
        var didSave = false

        XCTAssertThrowsError(
            try Self.loader(
                resources: resources,
                privateKey: privateKey
            ).loadBundledTrust(
                persistedRevocationState: TrustedModelRevocationState()
            ) { _ in
                didSave = true
            }
        ) {
            XCTAssertEqual(
                $0 as? ModelRevocationVerificationError,
                .contentHashMismatch
            )
        }
        XCTAssertFalse(didSave)
    }

    func testBundledTrustRejectsRevocationRollbackWithoutSaving() throws {
        let resources = try Self.makeResourceDirectory()
        defer { try? FileManager.default.removeItem(at: resources) }
        try Self.copyProductionCatalog(to: resources)
        let privateKey = Curve25519.Signing.PrivateKey()
        try Self.write(
            ModelRevocationTestFixture.snapshot(
                revision: "2026-07-30T00:00:00Z",
                records: [],
                privateKey: privateKey
            ),
            to: resources
        )
        let newerState = try TrustedModelRevocationState(
            snapshots: [
                ModelRevocationTestFixture.snapshot(
                    revision: "2026-07-31T00:00:00Z",
                    records: [],
                    privateKey: privateKey
                ),
            ]
        )
        var didSave = false

        XCTAssertThrowsError(
            try Self.loader(
                resources: resources,
                privateKey: privateKey
            ).loadBundledTrust(
                persistedRevocationState: newerState
            ) { _ in
                didSave = true
            }
        ) {
            XCTAssertEqual(
                $0 as? TrustedModelRevocationStateError,
                .rollback(
                    candidateRevision: "2026-07-30T00:00:00Z",
                    highestAcceptedRevision: "2026-07-31T00:00:00Z"
                )
            )
        }
        XCTAssertFalse(didSave)
    }

    private static func loader(
        resources: URL,
        privateKey: Curve25519.Signing.PrivateKey
    ) -> ProductionModelManifestLoader {
        ProductionModelManifestLoader(
            configuration: ProductionModelInstallConfiguration(
                trustedKeys: ProductionModelCatalogTrust.trustedKeys + [
                    TrustedModelManifestKey(
                        keyId: "revocation-test-key",
                        publicKeyBase64:
                            privateKey.publicKey.rawRepresentation
                                .base64EncodedString()
                    ),
                ]
            ),
            resourceDirectory: resources
        )
    }

    private static func makeResourceDirectory() throws -> URL {
        let resources = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TextifyBundledRevocations-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: catalogDirectory(in: resources),
            withIntermediateDirectories: true
        )
        return resources
    }

    private static func catalogDirectory(in resources: URL) -> URL {
        resources.appendingPathComponent(
            ProductionModelManifestLoader.bundledDirectoryName,
            isDirectory: true
        )
    }

    private static func copyProductionCatalog(to resources: URL) throws {
        let source = repositoryRoot
            .appendingPathComponent("models", isDirectory: true)
        let destination = catalogDirectory(in: resources)
        for name in [
            ProductionModelManifestLoader.bundledManifestName,
            ProductionModelManifestLoader.bundledSignatureName,
        ] {
            try FileManager.default.copyItem(
                at: source.appendingPathComponent(name),
                to: destination.appendingPathComponent(name)
            )
        }
    }

    private static func write(
        _ snapshot: TrustedModelRevocationSnapshot,
        to resources: URL
    ) throws {
        let directory = catalogDirectory(in: resources)
        try snapshot.revocationData.write(
            to: directory.appendingPathComponent(
                ProductionModelManifestLoader.bundledRevocationName
            )
        )
        try snapshot.signatureData.write(
            to: directory.appendingPathComponent(
                ProductionModelManifestLoader
                    .bundledRevocationSignatureName
            )
        )
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private enum FixtureError: Error, Equatable {
    case persistenceUnavailable
}
