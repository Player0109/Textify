import Foundation
@testable import TextifyModels
import XCTest

final class ModelStorageInventoryTests: XCTestCase {
    func testInventoryMeasuresFilesDirectoriesAndUnexpectedArtifactData() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let record = try fixture.installModel(id: "artifact-a")
        let artifactRoot = try fixture.layout.installedModelDirectory(modelID: "artifact-a")
        let extraDirectory = artifactRoot.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(
            at: extraDirectory,
            withIntermediateDirectories: true
        )
        try Data(repeating: 7, count: 8192).write(
            to: extraDirectory.appendingPathComponent("compiled.bin")
        )

        let snapshot = try await fixture.scanner.scan(installedRecords: [record])
        let artifact = try XCTUnwrap(snapshot.artifact(for: "artifact-a"))

        XCTAssertEqual(artifact.condition, .complete)
        XCTAssertEqual(artifact.presentExpectedFileCount, 1)
        XCTAssertEqual(artifact.expectedFileCount, 1)
        XCTAssertEqual(artifact.unexpectedFileCount, 1)
        XCTAssertGreaterThan(try XCTUnwrap(artifact.onDiskBytes), 0)
        XCTAssertEqual(
            snapshot.summary.totalManagedStorageBytes,
            snapshot.summary.installedModelStorageBytes
                + snapshot.summary.downloadStorageBytes
                + snapshot.summary.otherModelDataBytes
        )
    }

    func testMissingExpectedFileRetainsReceiptAndNeedsRepair() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let record = try fixture.record(id: "artifact-missing")

        let snapshot = try await fixture.scanner.scan(installedRecords: [record])
        let artifact = try XCTUnwrap(snapshot.artifact(for: "artifact-missing"))

        XCTAssertTrue(artifact.installationReceiptPresent)
        XCTAssertEqual(artifact.condition, .needsRepair)
        XCTAssertEqual(artifact.presentExpectedFileCount, 0)
        XCTAssertEqual(artifact.missingExpectedRelativePaths, ["model.bin"])
        XCTAssertEqual(artifact.onDiskBytes, 0)
        XCTAssertEqual(snapshot.summary.installedArtifactCount, 1)
    }

    func testCanonicalizedArtifactInventoriesOriginalStorageAndRetainsMissingReceipt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let canonical = try fixture.record(id: "canonical-artifact")
        let storageID = "custom-sha256-\(canonical.model.files[0].sha256)"
        let storedURL = try fixture.layout.installedFileURL(
            modelID: storageID,
            filename: canonical.model.files[0].filename
        )
        try FileManager.default.createDirectory(
            at: storedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let fixtureURL = try XCTUnwrap(
            Bundle.module.url(
                forResource: "model.bin",
                withExtension: nil,
                subdirectory: "Fixtures/Models"
            )
        )
        try Data(contentsOf: fixtureURL).write(to: storedURL)
        let record = InstalledModelRecord(
            model: canonical.model,
            installedAt: canonical.installedAt,
            localFilesByManifestFilename: [
                canonical.model.files[0].filename: storedURL.path,
            ],
            storageModelID: storageID,
            identityHistory: InstalledModelIdentityHistory(
                wasCurated: true,
                customImport: CustomModelImportHistory(
                    contentDigest: canonical.model.artifactTypedDigests()[0],
                    localNames: ["Imported Name"],
                    sourceFilenames: ["local.ggml"]
                )
            )
        )

        let complete = try await fixture.scanner.scan(installedRecords: [record])
        XCTAssertEqual(
            complete.artifact(for: canonical.model.id)?.condition,
            .complete
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(complete.artifact(for: canonical.model.id)?.onDiskBytes),
            0
        )

        try FileManager.default.removeItem(at: storedURL)
        let missing = try await fixture.scanner.scan(installedRecords: [record])
        let missingArtifact = try XCTUnwrap(
            missing.artifact(for: canonical.model.id)
        )
        XCTAssertTrue(missingArtifact.installationReceiptPresent)
        XCTAssertEqual(missingArtifact.condition, .needsRepair)
        XCTAssertEqual(missingArtifact.missingExpectedRelativePaths, ["model.bin"])
    }

    func testSymlinkInsideArtifactNeverCountsExternalTargetBytes() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let record = try fixture.installModel(id: "artifact-symlink")
        let artifactRoot = try fixture.layout.installedModelDirectory(
            modelID: "artifact-symlink"
        )
        let external = fixture.root
            .deletingLastPathComponent()
            .appendingPathComponent("external-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: external) }
        try Data(repeating: 3, count: 2_000_000).write(to: external)

        let before = try await fixture.scanner.scan(installedRecords: [record])
        try FileManager.default.createSymbolicLink(
            at: artifactRoot.appendingPathComponent("external-link"),
            withDestinationURL: external
        )
        let after = try await fixture.scanner.scan(installedRecords: [record])
        let beforeBytes = try XCTUnwrap(before.artifact(for: "artifact-symlink")?.onDiskBytes)
        let afterArtifact = try XCTUnwrap(after.artifact(for: "artifact-symlink"))

        XCTAssertEqual(afterArtifact.condition, .complete)
        XCTAssertEqual(afterArtifact.unexpectedFileCount, 1)
        XCTAssertLessThan(
            try XCTUnwrap(afterArtifact.onDiskBytes) - beforeBytes,
            Int64(2_000_000)
        )
    }

    func testSymlinkedArtifactRootCannotEscapeManagedStorage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let record = try fixture.record(id: "artifact-root-link")
        let externalRoot = fixture.root
            .deletingLastPathComponent()
            .appendingPathComponent(
                "external-artifact-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: externalRoot) }
        try FileManager.default.createDirectory(
            at: externalRoot,
            withIntermediateDirectories: true
        )
        try Data(repeating: 2, count: 2_000_000).write(
            to: externalRoot.appendingPathComponent("model.bin")
        )
        try FileManager.default.createDirectory(
            at: fixture.layout.installedModelsDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.layout.installedModelsDirectory
                .appendingPathComponent("artifact-root-link"),
            withDestinationURL: externalRoot
        )

        let snapshot = try await fixture.scanner.scan(installedRecords: [record])
        let artifact = try XCTUnwrap(
            snapshot.artifact(for: "artifact-root-link")
        )

        XCTAssertEqual(artifact.condition, .needsRepair)
        XCTAssertNil(artifact.onDiskBytes)
        XCTAssertEqual(snapshot.summary.installedModelStorageBytes, 0)
        XCTAssertLessThan(snapshot.summary.totalManagedStorageBytes, 2_000_000)
    }

    func testHardLinkedBytesAreDeduplicatedAcrossArtifactRoots() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.installModel(id: "artifact-a")
        let second = try fixture.record(id: "artifact-b")
        let secondRoot = try fixture.layout.installedModelDirectory(modelID: "artifact-b")
        try FileManager.default.createDirectory(
            at: secondRoot,
            withIntermediateDirectories: true
        )
        let before = try await fixture.scanner.scan(installedRecords: [first, second])
        let firstFile = try fixture.layout.installedFileURL(
            modelID: "artifact-a",
            filename: "model.bin"
        )
        let hardLink = secondRoot.appendingPathComponent("shared.bin")
        try FileManager.default.linkItem(at: firstFile, to: hardLink)

        let after = try await fixture.scanner.scan(installedRecords: [first, second])

        XCTAssertEqual(
            after.summary.installedModelStorageBytes,
            before.summary.installedModelStorageBytes
        )
        XCTAssertEqual(after.artifact(for: "artifact-b")?.unexpectedFileCount, 1)
    }

    func testDuplicateReceiptsProduceOneArtifactAndOneStorageCharge() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let record = try fixture.installModel(id: "artifact-duplicate")

        let single = try await fixture.scanner.scan(installedRecords: [record])
        let duplicate = try await fixture.scanner.scan(
            installedRecords: [record, record]
        )

        XCTAssertEqual(duplicate.artifacts.map(\.artifactID), ["artifact-duplicate"])
        XCTAssertEqual(duplicate.summary.installedArtifactCount, 1)
        XCTAssertEqual(
            duplicate.summary.installedModelStorageBytes,
            single.summary.installedModelStorageBytes
        )
        XCTAssertEqual(
            duplicate.summary.totalManagedStorageBytes,
            single.summary.totalManagedStorageBytes
        )
    }

    func testInstalledStoreNormalizesDuplicateReceiptsOnInitAndDecode() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.record(id: "artifact-duplicate")
        let latest = InstalledModelRecord(
            model: first.model,
            installedAt: "2026-07-24T12:00:00Z",
            localFilesByManifestFilename: first.localFilesByManifestFilename
        )

        let initialized = InstalledModelsStore(records: [first, latest])
        XCTAssertEqual(initialized.records, [latest])

        let encodedDuplicates = try JSONEncoder().encode([
            "records": [first, latest],
        ])
        let decoded = try JSONDecoder().decode(
            InstalledModelsStore.self,
            from: encodedDuplicates
        )
        XCTAssertEqual(decoded.records, [latest])
    }

    func testValidPartialIsDownloadStorageAndAllOtherManagedDataIsOther() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.layout.downloadsDirectory,
            withIntermediateDirectories: true
        )
        let partial = try fixture.layout.temporaryDownloadURL(
            modelID: "artifact-a",
            filename: "model.bin"
        )
        let metadataURL = try fixture.layout.downloadResumeMetadataURL(
            modelID: "artifact-a",
            filename: "model.bin"
        )
        let partialData = Data(repeating: 5, count: 8192)
        try partialData.write(to: partial)
        let metadata = DownloadResumeMetadata(
            modelID: "artifact-a",
            url: "https://github.com/Player0109/Textify/releases/download/models-v1/model.bin",
            expectedSize: 16384,
            sha256: String(repeating: "a", count: 64),
            eTag: "\"fixture\"",
            lastModified: nil,
            bytesDownloaded: Int64(partialData.count)
        )
        try JSONEncoder().encode(metadata).write(to: metadataURL)
        try Data("unattributed".utf8).write(
            to: fixture.layout.downloadsDirectory.appendingPathComponent("orphan.partial")
        )

        let snapshot = try await fixture.scanner.scan(installedRecords: [])

        XCTAssertGreaterThan(snapshot.summary.downloadStorageBytes, 0)
        XCTAssertGreaterThan(snapshot.summary.otherModelDataBytes, 0)
        XCTAssertEqual(
            snapshot.summary.totalManagedStorageBytes,
            snapshot.summary.downloadStorageBytes
                + snapshot.summary.otherModelDataBytes
        )
        XCTAssertEqual(snapshot.summary.availableSpaceBytes, 123_456_789)
    }
}

private extension ModelStorageInventoryTests {
    final class Fixture {
        let root: URL
        let layout: ModelStorageLayout
        let scanner: ModelStorageInventoryScanner
        private let sourceModel: ModelEntry
        private let modelData: Data

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "TextifyStorageInventory-\(UUID().uuidString)",
                    isDirectory: true
                )
            layout = ModelStorageLayout(rootDirectory: root)
            scanner = ModelStorageInventoryScanner(
                layout: layout,
                availableCapacity: { _ in 123_456_789 }
            )
            let manifestURL = try XCTUnwrap(
                Bundle.module.url(
                    forResource: "manifest.json",
                    withExtension: nil,
                    subdirectory: "Fixtures/Models"
                )
            )
            sourceModel = try XCTUnwrap(
                ModelManifest.decode(Data(contentsOf: manifestURL)).models.first
            )
            let modelURL = try XCTUnwrap(
                Bundle.module.url(
                    forResource: "model.bin",
                    withExtension: nil,
                    subdirectory: "Fixtures/Models"
                )
            )
            modelData = try Data(contentsOf: modelURL)
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }

        func record(id: String) throws -> InstalledModelRecord {
            let model = model(id: id)
            let installedFile = try layout.installedFileURL(
                modelID: id,
                filename: "model.bin"
            )
            return InstalledModelRecord(
                model: model,
                installedAt: "2026-07-24T00:00:00Z",
                localFilesByManifestFilename: ["model.bin": installedFile.path]
            )
        }

        func installModel(id: String) throws -> InstalledModelRecord {
            let record = try record(id: id)
            let installedFile = try layout.installedFileURL(
                modelID: id,
                filename: "model.bin"
            )
            try FileManager.default.createDirectory(
                at: installedFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try modelData.write(to: installedFile)
            return record
        }

        private func model(id: String) -> ModelEntry {
            ModelEntry(
                id: id,
                displayName: sourceModel.displayName,
                tier: sourceModel.tier,
                description: sourceModel.description,
                sizeBytes: sourceModel.sizeBytes,
                files: sourceModel.files,
                licenses: sourceModel.licenses,
                provenance: sourceModel.provenance,
                runtimeParameters: sourceModel.runtimeParameters,
                hallucinationThresholds: sourceModel.hallucinationThresholds,
                minAppVersion: sourceModel.minAppVersion,
                runtime: sourceModel.runtime,
                capabilities: sourceModel.capabilities
            )
        }
    }
}
