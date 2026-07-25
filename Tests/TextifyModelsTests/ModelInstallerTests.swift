import CryptoKit
import Foundation
import TextifyModels
import XCTest

final class ModelInstallerTests: XCTestCase {
    func testInstallerReportsStagingBeforeReceiptPersistence() async throws {
        let manifest = try Self.fixtureManifest()
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let root = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = ModelWorkflowBoundaryRecorder()
        let installer = ModelInstaller(
            layout: ModelStorageLayout(rootDirectory: root),
            transport: FixtureFileDownloadTransport(
                dataByURL: [
                    try XCTUnwrap(URL(string: file.url)):
                        try Self.fixtureData("model.bin"),
                ]
            ),
            durabilityObserver: recorder.observer
        )

        _ = try await installer.install(modelID: model.id, from: manifest)

        XCTAssertEqual(
            recorder.events.map(\.boundary),
            [.installationStaged, .installationReceiptPersisted]
        )
        XCTAssertEqual(
            Set(recorder.events.compactMap(\.artifactID)),
            [model.id]
        )
    }

    func testProductionPolicyAcceptsFixtureManifest() throws {
        try ProductionModelPolicy.validateV1_1ProductionManifest(try Self.fixtureManifest())
    }

    func testProductionPolicyRejectsArbitraryModelImport() throws {
        let manifest = try Self.fixtureManifest(replacingModelID: "custom-local-model")

        XCTAssertThrowsError(try ProductionModelPolicy.validateV1_1ProductionManifest(manifest)) { error in
            XCTAssertEqual(error as? ProductionModelPolicyError, .wrongModelID("custom-local-model"))
        }
    }

    func testInstallerDownloadsVerifiesAndStoresModel() async throws {
        let manifest = try Self.fixtureManifest()
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let layout = ModelStorageLayout(rootDirectory: rootDirectory)
        let modelData = try Self.fixtureData("model.bin")
        let transport = FixtureFileDownloadTransport(dataByURL: [
            try XCTUnwrap(URL(string: file.url)): modelData
        ])
        let installer = ModelInstaller(
            layout: layout,
            transport: transport,
            nowISO8601: { "2026-07-03T00:00:00Z" }
        )

        let record = try await installer.install(modelID: ProductionModelPolicy.requiredModelID, from: manifest)

        let installedURL = try layout.installedFileURL(modelID: model.id, filename: file.filename)
        XCTAssertEqual(record.model.id, ProductionModelPolicy.requiredModelID)
        XCTAssertEqual(record.localFilesByManifestFilename[file.filename], installedURL.path)
        XCTAssertEqual(try Data(contentsOf: installedURL), modelData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try layout.temporaryDownloadURL(modelID: model.id, filename: file.filename).path))

        let storeData = try Data(contentsOf: layout.installedStoreURL)
        let store = try JSONDecoder().decode(InstalledModelsStore.self, from: storeData)
        XCTAssertEqual(store.record(forModelID: model.id)?.installedAt, "2026-07-03T00:00:00Z")
    }

    func testInstallerAtomicallyStagesMultiFileDirectoryModel() async throws {
        let preprocessorData = Data("compiled preprocessor".utf8)
        let vocabularyData = Data("{\"0\":\"hello\"}".utf8)
        let manifest = try Self.directoryModelManifest(
            files: [
                (
                    filename: "parakeet-preprocessor-coremldata.bin",
                    relativePath: "Preprocessor.mlmodelc/coremldata.bin",
                    data: preprocessorData
                ),
                (
                    filename: "parakeet-vocabulary.json",
                    relativePath: "parakeet_vocab.json",
                    data: vocabularyData
                )
            ]
        )
        let model = try XCTUnwrap(manifest.models.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let layout = ModelStorageLayout(rootDirectory: rootDirectory)
        let dataByURL = Dictionary(uniqueKeysWithValues: try model.files.map { file in
            let data = file.filename.contains("vocabulary") ? vocabularyData : preprocessorData
            return (try XCTUnwrap(URL(string: file.url)), data)
        })
        let installer = ModelInstaller(
            layout: layout,
            transport: FixtureFileDownloadTransport(dataByURL: dataByURL),
            nowISO8601: { "2026-07-19T00:00:00Z" }
        )

        let record = try await installer.install(modelID: model.id, from: manifest)

        let preprocessorURL = try layout.installedArtifactURL(
            modelID: model.id,
            relativePath: "Preprocessor.mlmodelc/coremldata.bin"
        )
        let vocabularyURL = try layout.installedArtifactURL(
            modelID: model.id,
            relativePath: "parakeet_vocab.json"
        )
        XCTAssertEqual(try Data(contentsOf: preprocessorURL), preprocessorData)
        XCTAssertEqual(try Data(contentsOf: vocabularyURL), vocabularyData)
        XCTAssertEqual(
            record.localFilesByManifestFilename["parakeet-preprocessor-coremldata.bin"],
            preprocessorURL.path
        )
        XCTAssertEqual(
            record.localFilesByManifestFilename["parakeet-vocabulary.json"],
            vocabularyURL.path
        )
        XCTAssertEqual(record.installedAt, "2026-07-19T00:00:00Z")
    }

    func testRevokedDirectoryInstallCanRetainAlreadyValidatedStaging() async throws {
        let firstData = Data("compiled preprocessor".utf8)
        let secondData = Data("{\"0\":\"hello\"}".utf8)
        let manifest = try Self.directoryModelManifest(
            files: [
                (
                    filename: "parakeet-preprocessor-coremldata.bin",
                    relativePath: "Preprocessor.mlmodelc/coremldata.bin",
                    data: firstData
                ),
                (
                    filename: "parakeet-vocabulary.json",
                    relativePath: "parakeet_vocab.json",
                    data: secondData
                ),
            ]
        )
        let model = try XCTUnwrap(manifest.models.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let layout = ModelStorageLayout(rootDirectory: rootDirectory)
        let transport = CancellableSecondFileTransport(
            dataByURL: Dictionary(
                uniqueKeysWithValues: try model.files.map { file in
                    (
                        try XCTUnwrap(URL(string: file.url)),
                        file.filename.contains("vocabulary")
                            ? secondData
                            : firstData
                    )
                }
            )
        )
        let installer = ModelInstaller(
            layout: layout,
            transport: transport,
            retainsValidatedStagingOnCancellation: true
        )

        let task = Task {
            try await installer.install(
                modelID: model.id,
                from: manifest
            )
        }
        for _ in 0..<2_000 where !transport.isSecondDownloadStarted {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(transport.isSecondDownloadStarted)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation.")
        } catch is CancellationError {
            // Revocation cancels at a durable boundary.
        }

        let stagingDirectories = try FileManager.default
            .contentsOfDirectory(
                at: layout.downloadsDirectory,
                includingPropertiesForKeys: nil
            )
            .filter {
                $0.lastPathComponent.hasPrefix(
                    ".\(model.id).installing-"
                )
            }
        let stagingDirectory = try XCTUnwrap(stagingDirectories.first)
        let stagedFile = stagingDirectory.appendingPathComponent(
            "Preprocessor.mlmodelc/coremldata.bin"
        )
        XCTAssertEqual(try Data(contentsOf: stagedFile), firstData)
    }

    func testInstallerReportsDownloadAndInstallProgress() async throws {
        let manifest = try Self.fixtureManifest()
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let modelData = try Self.fixtureData("model.bin")
        let transport = FixtureFileDownloadTransport(
            dataByURL: [
                try XCTUnwrap(URL(string: file.url)): modelData
            ],
            progressEvents: [
                DownloadFileProgress(bytesDownloaded: 1, totalBytes: Int64(modelData.count)),
                DownloadFileProgress(bytesDownloaded: Int64(modelData.count), totalBytes: Int64(modelData.count))
            ]
        )
        let installer = ModelInstaller(
            layout: ModelStorageLayout(rootDirectory: rootDirectory),
            transport: transport
        )
        let recorder = InstallStateRecorder()

        _ = try await installer.install(
            modelID: ProductionModelPolicy.requiredModelID,
            from: manifest,
            onStateChange: { state in
                recorder.append(state)
            }
        )

        let states = recorder.states()
        XCTAssertEqual(states.map(\.phase), [
            .checkingSpace,
            .downloading,
            .downloading,
            .downloading,
            .verifying,
            .installing,
            .installed
        ])
        XCTAssertTrue(states.contains { state in
            state.phase == .downloading
                && state.bytesDownloaded == 1
                && state.totalBytes == Int64(modelData.count)
        })
        XCTAssertEqual(states.last?.progressFraction, 1)
    }

    func testInstallerRejectsInsufficientDiskSpaceBeforeDownload() async throws {
        let manifest = try Self.fixtureManifest()
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let transport = FixtureFileDownloadTransport(dataByURL: [
            try XCTUnwrap(URL(string: file.url)): try Self.fixtureData("model.bin")
        ])
        let installer = ModelInstaller(
            layout: ModelStorageLayout(rootDirectory: rootDirectory),
            transport: transport,
            availableCapacity: { _ in 100 }
        )
        let recorder = InstallStateRecorder()
        let requiredBytes = ModelDownloader.requiredFreeBytes(modelSizeBytes: file.sizeBytes)

        do {
            _ = try await installer.install(
                modelID: model.id,
                from: manifest,
                onStateChange: { recorder.append($0) }
            )
            XCTFail("Expected insufficient disk space")
        } catch let error as ModelInstallError {
            XCTAssertEqual(error, .insufficientDiskSpace(requiredBytes: requiredBytes, availableBytes: 100))
        }

        XCTAssertEqual(transport.downloadFileCallCount, 0)
        XCTAssertEqual(recorder.states().map(\.phase), [.checkingSpace, .failed])
    }

    func testInstallerSubtractsOnlyAllocatedValidatorBoundResumeCredit() async throws {
        let manifest = try Self.fixtureManifest()
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let layout = ModelStorageLayout(rootDirectory: rootDirectory)
        try FileManager.default.createDirectory(
            at: layout.downloadsDirectory,
            withIntermediateDirectories: true
        )
        let partialURL = try layout.temporaryDownloadURL(
            modelID: model.id,
            filename: file.filename
        )
        let metadataURL = try layout.downloadResumeMetadataURL(
            modelID: model.id,
            filename: file.filename
        )
        try Data(repeating: 1, count: 10).write(to: partialURL)
        try JSONEncoder().encode(
            DownloadResumeMetadata(
                modelID: model.id,
                url: file.url,
                expectedSize: file.sizeBytes,
                sha256: file.sha256,
                eTag: "\"fixture\"",
                lastModified: nil,
                bytesDownloaded: 10
            )
        ).write(to: metadataURL)
        let requirement = ModelStorageAdmissionRequirement(
            completeTransferBytes: model.sizeBytes,
            finalArtifactBytes: 33,
            peakInstallationBytes: 33
        )
        let available = requirement.requiredAdditionalCapacity(
            reusable: ModelReusableStorage(
                validatedLogicalBytes: 10,
                allocatedBytes: 10
            )
        )
        let transport = FixtureFileDownloadTransport(dataByURL: [
            try XCTUnwrap(URL(string: file.url)): try Self.fixtureData("model.bin"),
        ])
        let installer = ModelInstaller(
            layout: layout,
            transport: transport,
            availableCapacity: { _ in available }
        )

        _ = try await installer.install(modelID: model.id, from: manifest)

        XCTAssertEqual(transport.downloadFileCallCount, 1)
    }

    func testInstallerDoesNotCreditPartialFromOlderArtifactRevision() async throws {
        let manifest = try Self.fixtureManifest()
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let layout = ModelStorageLayout(rootDirectory: rootDirectory)
        try FileManager.default.createDirectory(
            at: layout.downloadsDirectory,
            withIntermediateDirectories: true
        )
        let partialURL = try layout.temporaryDownloadURL(
            modelID: model.id,
            filename: file.filename
        )
        let metadataURL = try layout.downloadResumeMetadataURL(
            modelID: model.id,
            filename: file.filename
        )
        try Data(repeating: 1, count: 10).write(to: partialURL)
        try JSONEncoder().encode(
            DownloadResumeMetadata(
                modelID: model.id,
                url: file.url,
                expectedSize: file.sizeBytes,
                sha256: String(repeating: "0", count: 64),
                eTag: "\"old-revision\"",
                lastModified: nil,
                bytesDownloaded: 10
            )
        ).write(to: metadataURL)
        let requirement = ModelStorageAdmissionRequirement(
            completeTransferBytes: model.sizeBytes,
            finalArtifactBytes: model.sizeBytes,
            peakInstallationBytes: model.sizeBytes
        )
        let capacityWithUnsafeCredit = requirement
            .requiredAdditionalCapacity(
                reusable: ModelReusableStorage(
                    validatedLogicalBytes: 10,
                    allocatedBytes: 10
                )
            )
        let transport = FixtureFileDownloadTransport(dataByURL: [
            try XCTUnwrap(URL(string: file.url)):
                try Self.fixtureData("model.bin"),
        ])
        let installer = ModelInstaller(
            layout: layout,
            transport: transport,
            availableCapacity: { _ in capacityWithUnsafeCredit }
        )

        do {
            _ = try await installer.install(
                modelID: model.id,
                from: manifest
            )
            XCTFail("Expected stale partial credit to be rejected.")
        } catch let error as ModelInstallError {
            XCTAssertEqual(
                error,
                .insufficientDiskSpace(
                    requiredBytes: requirement
                        .requiredAdditionalCapacity(reusable: .none),
                    availableBytes: capacityWithUnsafeCredit
                )
            )
        }
        XCTAssertEqual(transport.downloadFileCallCount, 0)
    }

    func testInstallerRechecksCapacityDuringTransferAndPreservesRetryablePartial() async throws {
        let manifest = try Self.fixtureManifest()
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let layout = ModelStorageLayout(rootDirectory: rootDirectory)
        let capacities = CapacitySequence([
            1_000_000_000,
            0,
        ])
        let transport = AdmissionCheckingDownloadTransport(
            data: try Self.fixtureData("model.bin"),
            expectedSHA256: file.sha256
        )
        let installer = ModelInstaller(
            layout: layout,
            transport: transport,
            capacityRecheckIntervalBytes: 1,
            availableCapacity: { _ in capacities.next() }
        )

        do {
            _ = try await installer.install(modelID: model.id, from: manifest)
            XCTFail("Expected transfer-time storage rejection")
        } catch let error as ModelInstallError {
            guard case .insufficientDiskSpace = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(transport.admissionCheckCount, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: layout.installedStoreURL.path
            )
        )
        let reusable = try ModelInstallResumableDataInspector(
            layout: layout
        ).inspect(
            for: ModelInstallQueueAttempt(
                id: "retry",
                artifactID: model.id,
                purpose: model.purpose,
                action: .install,
                createdAt: "2026-07-24T00:00:00Z",
                state: DownloadState(
                    modelID: model.id,
                    phase: .failed
                )
            ),
            expectedFiles: model.files
        )
        XCTAssertGreaterThan(reusable?.validatedBytes ?? 0, 0)
        XCTAssertLessThan(reusable?.validatedBytes ?? .max, file.sizeBytes)
    }

    func testInstallerRechecksCapacityBeforeDirectoryStaging() async throws {
        let first = Data("first".utf8)
        let second = Data("second".utf8)
        let manifest = try Self.directoryModelManifest(files: [
            (
                filename: "first.bin",
                relativePath: "Model/first.bin",
                data: first
            ),
            (
                filename: "second.bin",
                relativePath: "Model/second.bin",
                data: second
            ),
        ])
        let model = try XCTUnwrap(manifest.models.first)
        let capacities = CapacitySequence([
            1_000_000_000,
            1_000_000_000,
            1_000_000_000,
            1_000_000_000,
            0,
        ])
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let transport = FixtureFileDownloadTransport(
            dataByURL: Dictionary(
                uniqueKeysWithValues: try model.files.map {
                    (
                        try XCTUnwrap(URL(string: $0.url)),
                        $0.filename == "first.bin" ? first : second
                    )
                }
            )
        )
        let installer = ModelInstaller(
            layout: ModelStorageLayout(rootDirectory: rootDirectory),
            transport: transport,
            availableCapacity: { _ in capacities.next() }
        )

        do {
            _ = try await installer.install(modelID: model.id, from: manifest)
            XCTFail("Expected pre-staging storage rejection")
        } catch let error as ModelInstallError {
            guard case .insufficientDiskSpace = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(transport.downloadFileCallCount, 2)
    }

    func testInstallerRechecksCapacityAfterOutOfSpaceFailure() async throws {
        let manifest = try Self.fixtureManifest()
        let model = try XCTUnwrap(manifest.models.first)
        let capacities = CapacitySequence([
            1_000_000_000,
            10,
        ])
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let installer = ModelInstaller(
            layout: ModelStorageLayout(rootDirectory: rootDirectory),
            transport: OutOfSpaceDownloadTransport(),
            availableCapacity: { _ in capacities.next() }
        )

        do {
            _ = try await installer.install(modelID: model.id, from: manifest)
            XCTFail("Expected out-of-space storage rejection")
        } catch let error as ModelInstallError {
            guard case let .insufficientDiskSpace(_, availableBytes) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(availableBytes, 10)
        }

        XCTAssertEqual(capacities.callCount, 2)
    }

    func testInstallerFailsClosedWhenCapacityCannotBeMeasured() async throws {
        let manifest = try Self.fixtureManifest()
        let model = try XCTUnwrap(manifest.models.first)
        let installer = ModelInstaller(
            layout: ModelStorageLayout(
                rootDirectory: Self.temporaryDirectory()
            ),
            transport: FixtureFileDownloadTransport(dataByURL: [:]),
            availableCapacity: { _ in
                throw ModelStorageAdmissionError.capacityUnavailable
            }
        )

        do {
            _ = try await installer.install(modelID: model.id, from: manifest)
            XCTFail("Expected unavailable capacity rejection")
        } catch let error as ModelInstallError {
            XCTAssertEqual(error, .storageCapacityUnavailable)
        }
    }

    func testInstallerRejectsModelRequiringNewerAppVersionBeforeDownload() async throws {
        let manifest = try Self.fixtureManifest(replacingMinimumAppVersion: "1.2.0")
        let model = try XCTUnwrap(manifest.models.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let transport = FixtureFileDownloadTransport(dataByURL: [:])
        let installer = ModelInstaller(
            layout: ModelStorageLayout(rootDirectory: rootDirectory),
            transport: transport,
            currentAppVersion: "1.1.0"
        )

        do {
            _ = try await installer.install(modelID: model.id, from: manifest)
            XCTFail("Expected minimum app version rejection")
        } catch let error as ModelInstallError {
            XCTAssertEqual(
                error,
                .minimumAppVersionRequired(
                    modelID: model.id,
                    required: "1.2.0",
                    current: "1.1.0"
                )
            )
        }

        XCTAssertEqual(transport.downloadFileCallCount, 0)
    }

    func testInstallerDoesNotDownloadWhenInstalledRecordAndFileAreAlreadyValid() async throws {
        let manifest = try Self.fixtureManifest()
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let layout = ModelStorageLayout(rootDirectory: rootDirectory)
        let installedURL = try layout.installedFileURL(modelID: model.id, filename: file.filename)
        try FileManager.default.createDirectory(
            at: installedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let modelData = try Self.fixtureData("model.bin")
        try modelData.write(to: installedURL)
        try FileManager.default.createDirectory(
            at: layout.rootDirectory,
            withIntermediateDirectories: true
        )
        let existingRecord = InstalledModelRecord(
            model: model,
            installedAt: "2026-07-03T00:00:00Z",
            localFilesByManifestFilename: [file.filename: installedURL.path]
        )
        let storeData = try JSONEncoder().encode(InstalledModelsStore(records: [existingRecord]))
        try storeData.write(to: layout.installedStoreURL, options: [.atomic])
        let transport = FixtureFileDownloadTransport(dataByURL: [:])
        let installer = ModelInstaller(layout: layout, transport: transport)
        let recorder = InstallStateRecorder()

        let record = try await installer.install(
            modelID: ProductionModelPolicy.requiredModelID,
            from: manifest,
            onStateChange: { state in
                recorder.append(state)
            }
        )

        XCTAssertEqual(record, existingRecord)
        XCTAssertEqual(transport.downloadFileCallCount, 0)
        XCTAssertEqual(recorder.states().map(\.phase), [.installed])
        XCTAssertEqual(try Data(contentsOf: installedURL), modelData)
    }

    func testInstallerRefreshesSignedManifestMetadataWithoutRedownloadingValidBytes() async throws {
        let originalManifest = try Self.fixtureManifest()
        let updatedManifest = try Self.fixtureManifest(
            replacingDescription: "Updated signed model description."
        )
        let originalModel = try XCTUnwrap(originalManifest.models.first)
        let updatedModel = try XCTUnwrap(updatedManifest.models.first)
        let file = try XCTUnwrap(originalModel.files.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let layout = ModelStorageLayout(rootDirectory: rootDirectory)
        let installedURL = try layout.installedFileURL(
            modelID: originalModel.id,
            filename: file.filename
        )
        try FileManager.default.createDirectory(
            at: installedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.fixtureData("model.bin").write(to: installedURL)
        let existingRecord = InstalledModelRecord(
            model: originalModel,
            installedAt: "2026-07-03T00:00:00Z",
            localFilesByManifestFilename: [file.filename: installedURL.path],
            identityHistory: InstalledModelIdentityHistory(wasCurated: true)
        )
        try JSONEncoder()
            .encode(InstalledModelsStore(records: [existingRecord]))
            .write(to: layout.installedStoreURL, options: [.atomic])
        let transport = FixtureFileDownloadTransport(dataByURL: [:])
        let installer = ModelInstaller(layout: layout, transport: transport)

        let refreshed = try await installer.install(
            modelID: ProductionModelPolicy.requiredModelID,
            from: updatedManifest
        )

        XCTAssertEqual(transport.downloadFileCallCount, 0)
        XCTAssertEqual(refreshed.model, updatedModel)
        XCTAssertEqual(refreshed.installedAt, existingRecord.installedAt)
        XCTAssertEqual(
            refreshed.identityHistory,
            existingRecord.identityHistory
        )
        let stored = try JSONDecoder().decode(
            InstalledModelsStore.self,
            from: Data(contentsOf: layout.installedStoreURL)
        )
        XCTAssertEqual(stored.record(forModelID: originalModel.id), refreshed)
    }

    func testInstallerDeletesPartialOnChecksumMismatch() async throws {
        let manifest = try Self.fixtureManifest()
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let layout = ModelStorageLayout(rootDirectory: rootDirectory)
        let expectedData = try Self.fixtureData("model.bin")
        let transport = FixtureFileDownloadTransport(dataByURL: [
            try XCTUnwrap(URL(string: file.url)): Data(repeating: 0, count: expectedData.count)
        ])
        let installer = ModelInstaller(layout: layout, transport: transport)

        do {
            _ = try await installer.install(modelID: ProductionModelPolicy.requiredModelID, from: manifest)
            XCTFail("Expected checksum mismatch")
        } catch let error as ModelInstallError {
            switch error {
            case .checksumMismatch(expected: file.sha256, actual: _):
                break
            default:
                XCTFail("Unexpected install error: \(error)")
            }
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: try layout.temporaryDownloadURL(modelID: model.id, filename: file.filename).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.installedStoreURL.path))
    }

    func testInstallerDeletesDownloadWhoseSizeDoesNotMatchSignedManifest() async throws {
        let manifest = try Self.fixtureManifest()
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let layout = ModelStorageLayout(rootDirectory: rootDirectory)
        let oversizedData = try Self.fixtureData("model.bin") + Data([0])
        let transport = FixtureFileDownloadTransport(dataByURL: [
            try XCTUnwrap(URL(string: file.url)): oversizedData
        ])
        let installer = ModelInstaller(layout: layout, transport: transport)

        do {
            _ = try await installer.install(modelID: model.id, from: manifest)
            XCTFail("Expected signed-size mismatch")
        } catch let error as ModelInstallError {
            XCTAssertEqual(
                error,
                .unexpectedDownloadSize(
                    expectedBytes: file.sizeBytes,
                    actualBytes: Int64(oversizedData.count)
                )
            )
        }

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: try layout.temporaryDownloadURL(modelID: model.id, filename: file.filename).path
        ))
    }

    func testInstallerAcceptsAdditionalModelFromVerifiedCatalog() async throws {
        let manifest = try Self.fixtureManifest(replacingModelID: "custom-local-model")
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let transport = FixtureFileDownloadTransport(dataByURL: [
            try XCTUnwrap(URL(string: file.url)): try Self.fixtureData("model.bin")
        ])
        let installer = ModelInstaller(
            layout: ModelStorageLayout(rootDirectory: rootDirectory),
            transport: transport
        )

        let record = try await installer.install(modelID: model.id, from: manifest)

        XCTAssertEqual(record.model.id, "custom-local-model")
    }

    func testStorageLayoutRejectsTraversalModelID() throws {
        let layout = ModelStorageLayout(rootDirectory: Self.temporaryDirectory())

        XCTAssertThrowsError(try layout.installedModelDirectory(modelID: "../escape")) { error in
            XCTAssertEqual(error as? ModelStorageLayoutError, .unsafePathComponent("../escape"))
        }
    }

    func testInstallerRejectsTraversalFilename() async throws {
        let manifest = try Self.fixtureManifest(replacingFilename: "../model.bin")
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let installer = ModelInstaller(
            layout: ModelStorageLayout(rootDirectory: rootDirectory),
            transport: FixtureFileDownloadTransport(dataByURL: [:])
        )

        do {
            _ = try await installer.install(modelID: ProductionModelPolicy.requiredModelID, from: manifest)
            XCTFail("Expected unsafe filename rejection")
        } catch let error as ModelStorageLayoutError {
            XCTAssertEqual(error, .unsafePathComponent("../model.bin"))
        }
    }

    func testInstallerRejectsNonHTTPSModelFileURLBeforeDownload() async throws {
        let manifest = try Self.fixtureManifest(replacingFileURL: "http://github.com/Player0109/Textify/releases/download/models-v1/model.bin")
        let rootDirectory = Self.temporaryDirectory()
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let installer = ModelInstaller(
            layout: ModelStorageLayout(rootDirectory: rootDirectory),
            transport: FixtureFileDownloadTransport(dataByURL: [:])
        )

        do {
            _ = try await installer.install(modelID: ProductionModelPolicy.requiredModelID, from: manifest)
            XCTFail("Expected non-HTTPS model file URL rejection")
        } catch let error as ProductionModelPolicyError {
            XCTAssertEqual(
                error,
                .invalidModelFileURL(
                    modelID: ProductionModelPolicy.requiredModelID,
                    url: "http://github.com/Player0109/Textify/releases/download/models-v1/model.bin"
                )
            )
        }
    }

    func testInstallerRejectsWrongModelFileHostBeforeDownload() async throws {
        let manifest = try Self.fixtureManifest(replacingFileURL: "https://example.com/Player0109/Textify/releases/download/models-v1/model.bin")
        let rootDirectory = Self.temporaryDirectory()
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let installer = ModelInstaller(
            layout: ModelStorageLayout(rootDirectory: rootDirectory),
            transport: FixtureFileDownloadTransport(dataByURL: [:])
        )

        do {
            _ = try await installer.install(modelID: ProductionModelPolicy.requiredModelID, from: manifest)
            XCTFail("Expected unsupported model file URL rejection")
        } catch let error as ProductionModelPolicyError {
            XCTAssertEqual(
                error,
                .invalidModelFileURL(
                    modelID: ProductionModelPolicy.requiredModelID,
                    url: "https://example.com/Player0109/Textify/releases/download/models-v1/model.bin"
                )
            )
        }
    }

    func testInstallerAcceptsCommitPinnedHuggingFaceModelFile() async throws {
        let pinnedURL = "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/resolve/aed02740059203c4a87495924f685de3722ae9ce/parakeet_vocab.json"
        let manifest = try Self.fixtureManifest(replacingFileURL: pinnedURL)
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let modelData = try Self.fixtureData("model.bin")
        let installer = ModelInstaller(
            layout: ModelStorageLayout(rootDirectory: rootDirectory),
            transport: FixtureFileDownloadTransport(dataByURL: [
                try XCTUnwrap(URL(string: pinnedURL)): modelData
            ])
        )

        let record = try await installer.install(modelID: model.id, from: manifest)

        XCTAssertEqual(record.model.id, model.id)
        XCTAssertEqual(record.localFilesByManifestFilename.keys.sorted(), [file.filename])
    }

    func testExistingInstallUsesAtomicReplacementWithoutMovingInstalledFile() async throws {
        let manifest = try Self.fixtureManifest()
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let layout = ModelStorageLayout(rootDirectory: rootDirectory)
        let installedURL = try layout.installedFileURL(modelID: model.id, filename: file.filename)
        try FileManager.default.createDirectory(
            at: installedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existingData = Data("existing model bytes".utf8)
        try existingData.write(to: installedURL)
        let fileManager = InstalledPathRecordingFileManager(installedURL: installedURL)
        let fileReplacer = AtomicReplacementSpy(
            expectedInstalledURL: installedURL,
            expectedExistingData: existingData
        )
        let installer = ModelInstaller(
            layout: layout,
            transport: FixtureFileDownloadTransport(dataByURL: [
                try XCTUnwrap(URL(string: file.url)): try Self.fixtureData("model.bin")
            ]),
            fileManager: fileManager,
            fileReplacer: fileReplacer
        )

        _ = try await installer.install(modelID: ProductionModelPolicy.requiredModelID, from: manifest)

        XCTAssertEqual(fileReplacer.replacementCalls, 1)
        XCTAssertTrue(fileReplacer.installedFileExistedAtReplacement)
        XCTAssertEqual(fileReplacer.installedDataAtReplacement, existingData)
        XCTAssertFalse(fileManager.didMoveFromInstalledURL)
        XCTAssertFalse(fileManager.didMoveToInstalledURL)
        XCTAssertFalse(fileManager.didRemoveInstalledURL)
        XCTAssertEqual(try Data(contentsOf: installedURL), try Self.fixtureData("model.bin"))
    }

    func testReinstallRechecksSignedPeakBeforeReplacement() async throws {
        let manifest = try Self.fixtureManifest()
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let layout = ModelStorageLayout(rootDirectory: rootDirectory)
        let installedURL = try layout.installedFileURL(
            modelID: model.id,
            filename: file.filename
        )
        try FileManager.default.createDirectory(
            at: installedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existingData = Data("existing model bytes".utf8)
        try existingData.write(to: installedURL)
        let fileReplacer = AtomicReplacementSpy(
            expectedInstalledURL: installedURL,
            expectedExistingData: existingData
        )
        let capacities = CapacitySequence([
            1_000_000_000,
            1_000_000_000,
            0,
        ])
        let installer = ModelInstaller(
            layout: layout,
            transport: FixtureFileDownloadTransport(dataByURL: [
                try XCTUnwrap(URL(string: file.url)):
                    try Self.fixtureData("model.bin"),
            ]),
            fileReplacer: fileReplacer,
            availableCapacity: { _ in capacities.next() }
        )

        do {
            _ = try await installer.install(
                modelID: model.id,
                from: manifest
            )
            XCTFail("Expected the pre-replacement capacity check to fail.")
        } catch let error as ModelInstallError {
            XCTAssertEqual(
                error,
                .insufficientDiskSpace(
                    requiredBytes: 500_000_000,
                    availableBytes: 0
                )
            )
        }

        XCTAssertEqual(capacities.callCount, 3)
        XCTAssertEqual(fileReplacer.replacementCalls, 0)
        XCTAssertEqual(try Data(contentsOf: installedURL), existingData)
    }

    func testExistingInstalledFileSurvivesFailedAtomicReplacement() async throws {
        let manifest = try Self.fixtureManifest()
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let layout = ModelStorageLayout(rootDirectory: rootDirectory)
        let installedURL = try layout.installedFileURL(modelID: model.id, filename: file.filename)
        try FileManager.default.createDirectory(
            at: installedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existingData = Data("existing model bytes".utf8)
        try existingData.write(to: installedURL)
        let fileReplacer = AtomicReplacementSpy(
            expectedInstalledURL: installedURL,
            expectedExistingData: existingData,
            injectedError: AtomicReplacementFailure.injected
        )
        let installer = ModelInstaller(
            layout: layout,
            transport: FixtureFileDownloadTransport(dataByURL: [
                try XCTUnwrap(URL(string: file.url)): try Self.fixtureData("model.bin")
            ]),
            fileReplacer: fileReplacer
        )

        do {
            _ = try await installer.install(modelID: ProductionModelPolicy.requiredModelID, from: manifest)
            XCTFail("Expected atomic replacement failure")
        } catch AtomicReplacementFailure.injected {
            // Expected injected filesystem failure.
        }

        XCTAssertEqual(fileReplacer.replacementCalls, 1)
        XCTAssertEqual(try Data(contentsOf: installedURL), existingData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.installedStoreURL.path))
    }

    func testCancellationDoesNotRemoveExistingInstalledArtifact() async throws {
        let manifest = try Self.fixtureManifest()
        let model = try XCTUnwrap(manifest.models.first)
        let file = try XCTUnwrap(model.files.first)
        let rootDirectory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let layout = ModelStorageLayout(rootDirectory: rootDirectory)
        let installedURL = try layout.installedFileURL(
            modelID: model.id,
            filename: file.filename
        )
        try FileManager.default.createDirectory(
            at: installedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existingData = Data("existing model bytes".utf8)
        try existingData.write(to: installedURL)
        let existingRecord = InstalledModelRecord(
            model: model,
            installedAt: "2026-07-23T00:00:00Z",
            localFilesByManifestFilename: [
                file.filename: installedURL.path,
            ]
        )
        try JSONEncoder().encode(
            InstalledModelsStore(records: [existingRecord])
        ).write(to: layout.installedStoreURL, options: .atomic)
        let installer = ModelInstaller(
            layout: layout,
            transport: CancellationDownloadTransport()
        )

        do {
            _ = try await installer.install(
                modelID: model.id,
                from: manifest
            )
            XCTFail("Expected cancellation.")
        } catch is CancellationError {
            // Expected injected cancellation.
        }

        XCTAssertEqual(try Data(contentsOf: installedURL), existingData)
        let stored = try JSONDecoder().decode(
            InstalledModelsStore.self,
            from: Data(contentsOf: layout.installedStoreURL)
        )
        XCTAssertEqual(stored.record(forModelID: model.id), existingRecord)
    }

    private static func fixtureManifest(
        replacingModelID modelID: String? = nil,
        replacingFilename filename: String? = nil,
        replacingFileURL fileURL: String? = nil,
        replacingDescription description: String? = nil,
        replacingMinimumAppVersion minimumAppVersion: String? = nil
    ) throws -> ModelManifest {
        let manifest = try ModelManifest.decode(try fixtureData("manifest.json"))
        guard modelID != nil
                || filename != nil
                || fileURL != nil
                || description != nil
                || minimumAppVersion != nil
        else {
            return manifest
        }

        let models = manifest.models.map { model -> ModelEntry in
            let files = model.files.map { file in
                ModelFile(
                    filename: filename ?? file.filename,
                    url: fileURL ?? file.url,
                    sha256: file.sha256,
                    sizeBytes: file.sizeBytes
                )
            }
            return ModelEntry(
                id: modelID ?? model.id,
                displayName: model.displayName,
                tier: model.tier,
                description: description ?? model.description,
                sizeBytes: model.sizeBytes,
                files: files,
                licenses: model.licenses,
                provenance: model.provenance,
                runtimeParameters: model.runtimeParameters,
                hallucinationThresholds: model.hallucinationThresholds,
                minAppVersion: minimumAppVersion ?? model.minAppVersion,
                runtime: model.runtime,
                capabilities: model.capabilities,
                presentation: model.presentation,
                purpose: model.purpose,
                installationStorage: model.installationStorage,
                benchmark: model.benchmark
            )
        }
        return ModelManifest(
            manifestVersion: manifest.manifestVersion,
            generatedAt: manifest.generatedAt,
            models: models
        )
    }

    private static func directoryModelManifest(
        files: [(filename: String, relativePath: String, data: Data)]
    ) throws -> ModelManifest {
        let fixtureModel = try XCTUnwrap(try fixtureManifest().models.first)
        let modelFiles = files.map { file in
            ModelFile(
                filename: file.filename,
                relativePath: file.relativePath,
                url: "https://github.com/Player0109/Textify/releases/download/models-v2/\(file.filename)",
                sha256: sha256Hex(file.data),
                sizeBytes: Int64(file.data.count)
            )
        }
        let sizeBytes = modelFiles.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let model = ModelEntry(
            id: "parakeet-tdt-0.6b-v3",
            displayName: "Parakeet TDT 0.6B V3",
            tier: "fast",
            description: "Multilingual local dictation on Apple Neural Engine.",
            sizeBytes: sizeBytes,
            files: modelFiles,
            licenses: fixtureModel.licenses,
            provenance: fixtureModel.provenance,
            runtimeParameters: .legacyEnglishWhisper,
            hallucinationThresholds: fixtureModel.hallucinationThresholds,
            minAppVersion: "0.2.0",
            runtime: ModelRuntimeDescriptor(
                engine: .fluidAudioParakeet,
                variant: "parakeet-tdt-0.6b-v3",
                accelerator: .coreMLNeuralEngine,
                artifactLayout: .modelDirectory
            ),
            capabilities: ModelCapabilities(
                languages: ["en", "es", "de", "fr"],
                supportsTranslation: false,
                supportsCustomVocabulary: false
            ),
            presentation: nil,
            purpose: .transcription,
            installationStorage: ModelInstallationStorage(
                finalArtifactBytes: sizeBytes,
                peakInstallationBytes: sizeBytes
            ),
            benchmark: nil
        )
        return ModelManifest(
            manifestVersion: 1,
            generatedAt: "2026-07-19T00:00:00Z",
            models: [model]
        )
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

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

    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyModelsTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private final class FixtureFileDownloadTransport: DownloadTransport {
    private let dataByURL: [URL: Data]
    private let progressEvents: [DownloadFileProgress]
    private(set) var downloadFileCallCount = 0

    init(dataByURL: [URL: Data], progressEvents: [DownloadFileProgress] = []) {
        self.dataByURL = dataByURL
        self.progressEvents = progressEvents
    }

    func fetch(_ request: URLRequest) async throws -> DownloadResponse {
        guard let url = request.url, let data = dataByURL[url] else {
            throw FixtureFileDownloadTransportError.missingResponse
        }
        return DownloadResponse(data: data)
    }

    func downloadFile(_ request: URLRequest, to temporaryURL: URL) async throws -> DownloadFileResponse {
        downloadFileCallCount += 1
        let response = try await fetch(request)
        try response.data.write(to: temporaryURL)
        return DownloadFileResponse(fileURL: temporaryURL)
    }

    func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse {
        downloadFileCallCount += 1
        let response = try await fetch(request)
        for event in progressEvents {
            progress(event)
        }
        try response.data.write(to: temporaryURL)
        return DownloadFileResponse(fileURL: temporaryURL)
    }

    func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL,
        maximumBytes: Int64,
        admissionCheck: @escaping @Sendable (
            DownloadFileProgress
        ) throws -> Void,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse {
        downloadFileCallCount += 1
        let response = try await fetch(request)
        try response.data.write(to: temporaryURL)
        for event in progressEvents {
            try admissionCheck(event)
            progress(event)
        }
        let finalEvent = DownloadFileProgress(
            bytesDownloaded: Int64(response.data.count),
            totalBytes: Int64(response.data.count)
        )
        if progressEvents.last != finalEvent {
            try admissionCheck(finalEvent)
        }
        return DownloadFileResponse(fileURL: temporaryURL)
    }
}

private final class CancellableSecondFileTransport:
    DownloadTransport,
    @unchecked Sendable
{
    private let dataByURL: [URL: Data]
    private let lock = NSLock()
    private var downloadCount = 0
    private var secondDownloadStarted = false

    init(dataByURL: [URL: Data]) {
        self.dataByURL = dataByURL
    }

    var isSecondDownloadStarted: Bool {
        lock.withLock {
            secondDownloadStarted
        }
    }

    func fetch(_ request: URLRequest) async throws -> DownloadResponse {
        guard let url = request.url,
              let data = dataByURL[url]
        else {
            throw FixtureFileDownloadTransportError.missingResponse
        }
        return DownloadResponse(data: data)
    }

    func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL
    ) async throws -> DownloadFileResponse {
        try await download(request, to: temporaryURL)
    }

    func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL,
        maximumBytes: Int64,
        admissionCheck: @escaping @Sendable (
            DownloadFileProgress
        ) throws -> Void,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse {
        let response = try await download(request, to: temporaryURL)
        let byteCount = Int64(
            try Data(contentsOf: response.fileURL).count
        )
        let event = DownloadFileProgress(
            bytesDownloaded: byteCount,
            totalBytes: byteCount
        )
        try admissionCheck(event)
        progress(event)
        return response
    }

    private func download(
        _ request: URLRequest,
        to temporaryURL: URL
    ) async throws -> DownloadFileResponse {
        let callNumber = lock.withLock {
            downloadCount += 1
            if downloadCount == 2 {
                secondDownloadStarted = true
            }
            return downloadCount
        }
        if callNumber == 2 {
            try await Task.sleep(nanoseconds: .max)
        }
        let response = try await fetch(request)
        try response.data.write(to: temporaryURL)
        return DownloadFileResponse(fileURL: temporaryURL)
    }
}

private enum FixtureFileDownloadTransportError: Error {
    case missingResponse
}

private final class CapacitySequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int64]
    private(set) var callCount = 0

    init(_ values: [Int64]) {
        self.values = values
    }

    func next() -> Int64 {
        lock.withLock {
            callCount += 1
            return values.isEmpty ? 0 : values.removeFirst()
        }
    }
}

private final class AdmissionCheckingDownloadTransport: DownloadTransport {
    private let data: Data
    private let expectedSHA256: String
    private(set) var admissionCheckCount = 0

    init(data: Data, expectedSHA256: String) {
        self.data = data
        self.expectedSHA256 = expectedSHA256
    }

    func fetch(_ request: URLRequest) async throws -> DownloadResponse {
        DownloadResponse(data: data)
    }

    func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL
    ) async throws -> DownloadFileResponse {
        try data.write(to: temporaryURL)
        return DownloadFileResponse(fileURL: temporaryURL)
    }

    func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL,
        maximumBytes: Int64,
        admissionCheck: @escaping @Sendable (
            DownloadFileProgress
        ) throws -> Void,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse {
        let partialData = data.prefix(max(1, data.count / 2))
        try Data(partialData).write(to: temporaryURL)
        let event = DownloadFileProgress(
            bytesDownloaded: Int64(partialData.count),
            totalBytes: Int64(data.count)
        )
        admissionCheckCount += 1
        do {
            try admissionCheck(event)
        } catch {
            let metadata = DownloadResumeMetadata(
                modelID: ProductionModelPolicy.requiredModelID,
                url: request.url?.absoluteString ?? "",
                expectedSize: maximumBytes,
                sha256: expectedSHA256,
                eTag: "\"fixture\"",
                lastModified: nil,
                bytesDownloaded: Int64(partialData.count)
            )
            let metadataURL = temporaryURL.appendingPathExtension(
                "resume.json"
            )
            try JSONEncoder().encode(metadata).write(to: metadataURL)
            throw error
        }
        progress(event)
        return DownloadFileResponse(fileURL: temporaryURL)
    }
}

private struct OutOfSpaceDownloadTransport: DownloadTransport {
    func fetch(_ request: URLRequest) async throws -> DownloadResponse {
        throw POSIXError(.ENOSPC)
    }

    func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL
    ) async throws -> DownloadFileResponse {
        throw POSIXError(.ENOSPC)
    }

    func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL,
        maximumBytes: Int64,
        admissionCheck: @escaping @Sendable (
            DownloadFileProgress
        ) throws -> Void,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse {
        throw POSIXError(.ENOSPC)
    }
}

private struct CancellationDownloadTransport: DownloadTransport {
    func fetch(_ request: URLRequest) async throws -> DownloadResponse {
        throw CancellationError()
    }

    func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL
    ) async throws -> DownloadFileResponse {
        throw CancellationError()
    }

    func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL,
        maximumBytes: Int64,
        admissionCheck: @escaping @Sendable (
            DownloadFileProgress
        ) throws -> Void,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse {
        throw CancellationError()
    }
}

private final class InstallStateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedStates: [DownloadState] = []

    func append(_ state: DownloadState) {
        lock.lock()
        recordedStates.append(state)
        lock.unlock()
    }

    func states() -> [DownloadState] {
        lock.lock()
        let result = recordedStates
        lock.unlock()
        return result
    }
}

private final class InstalledPathRecordingFileManager: FileManager {
    private let installedURL: URL
    private(set) var didMoveFromInstalledURL = false
    private(set) var didMoveToInstalledURL = false
    private(set) var didRemoveInstalledURL = false

    init(installedURL: URL) {
        self.installedURL = installedURL.standardizedFileURL
        super.init()
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if srcURL.standardizedFileURL == installedURL {
            didMoveFromInstalledURL = true
        }
        if dstURL.standardizedFileURL == installedURL {
            didMoveToInstalledURL = true
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }

    override func removeItem(at URL: URL) throws {
        if URL.standardizedFileURL == installedURL {
            didRemoveInstalledURL = true
        }
        try super.removeItem(at: URL)
    }
}

private final class AtomicReplacementSpy: InstalledModelFileReplacing {
    private let expectedInstalledURL: URL
    private let expectedExistingData: Data
    private let injectedError: (any Error)?
    private(set) var replacementCalls = 0
    private(set) var installedFileExistedAtReplacement = false
    private(set) var installedDataAtReplacement: Data?

    init(
        expectedInstalledURL: URL,
        expectedExistingData: Data,
        injectedError: (any Error)? = nil
    ) {
        self.expectedInstalledURL = expectedInstalledURL.standardizedFileURL
        self.expectedExistingData = expectedExistingData
        self.injectedError = injectedError
    }

    func replaceExistingInstalledFile(at installedURL: URL, with replacementURL: URL) throws {
        replacementCalls += 1
        XCTAssertEqual(installedURL.standardizedFileURL, expectedInstalledURL)
        installedFileExistedAtReplacement = FileManager.default.fileExists(atPath: installedURL.path)
        installedDataAtReplacement = try? Data(contentsOf: installedURL)
        XCTAssertEqual(installedDataAtReplacement, expectedExistingData)
        if let injectedError {
            throw injectedError
        }
        _ = try FileManager.default.replaceItemAt(
            installedURL,
            withItemAt: replacementURL,
            backupItemName: nil,
            options: []
        )
    }
}

private enum AtomicReplacementFailure: Error {
    case injected
}
