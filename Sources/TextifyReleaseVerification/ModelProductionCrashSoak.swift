import CryptoKit
import Darwin
import Foundation
import TextifyModels

struct ModelProductionSoakRecoveryResult: Codable {
    let seed: UInt64
    let completedOperationCount: Int
    let operationCounts: [String: Int]
    let invariantViolations: [String]
    let unexplainedManagedBytes: Int64
}

struct ModelProductionSoakWorker {
    let root: URL
    let repositoryRoot: URL
    let seed: UInt64

    private var layout: ModelStorageLayout {
        ModelStorageLayout(
            rootDirectory: root.appendingPathComponent(
                "Models",
                isDirectory: true
            )
        )
    }

    private var progressURL: URL {
        root.appendingPathComponent("soak-progress.json")
    }

    private var catalogURL: URL {
        root.appendingPathComponent("trusted-catalog.json")
    }

    func perform(start: Int, end: Int) async throws {
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        var progress = try loadProgress()
        guard progress.seed == seed,
              progress.completedOperationCount == start
        else {
            throw SoakError.progressDisagreement
        }
        for operationIndex in start ..< end {
            let operation = operation(at: operationIndex)
            try await apply(
                operation,
                operationIndex: operationIndex
            )
            progress.completedOperationCount = operationIndex + 1
            progress.operationCounts[operation.rawValue, default: 0] += 1
            try saveProgress(progress)
        }
        Darwin._exit(
            ModelProductionFaultCampaign.forcedTerminationExitStatus
        )
    }

    func recover(expectedOperationCount: Int) async throws {
        var violations: [String] = []
        let progress = try loadProgress()
        if progress.seed != seed {
            violations.append("soak_seed_disagreement")
        }
        if progress.completedOperationCount != expectedOperationCount {
            violations.append("soak_operation_count_disagreement")
        }
        let expectedTypes = Set(SoakOperation.allCases.map(\.rawValue))
        if Set(progress.operationCounts.keys) != expectedTypes {
            violations.append("soak_operation_type_coverage_incomplete")
        }

        let queue = try ModelInstallQueueStore(
            fileURL: layout.installQueueURL
        ).loadForRelaunch()
        if queue.attempts.contains(where: {
            $0.state.phase != .cancelled
        }) {
            violations.append("soak_queue_not_recoverable")
        }

        let fixture = try modelFixture()
        let receiptStore = InstalledModelsStorePersistence(
            fileURL: layout.installedStoreURL
        )
        let record = try receiptStore.load()
            .record(forModelID: fixture.model.id)
        let installedURL = try layout.installedFileURL(
            modelID: fixture.model.id,
            filename: fixture.file.filename
        )
        if FileManager.default.fileExists(atPath: installedURL.path),
           record == nil
        {
            violations.append("soak_installed_payload_without_receipt")
        }
        if let record {
            guard let path =
                record.localFilesByManifestFilename[fixture.file.filename],
                let data = try? Data(
                    contentsOf: URL(fileURLWithPath: path)
                ),
                data == fixture.data
            else {
                violations.append("soak_receipt_payload_disagreement")
                try await installFixture()
                return try writeRecovery(
                    progress: progress,
                    violations: violations
                )
            }
        }
        try writeRecovery(
            progress: progress,
            violations: violations
        )
    }

    private func apply(
        _ operation: SoakOperation,
        operationIndex: Int
    ) async throws {
        switch operation {
        case .install:
            try await installFixture()
        case .reinstall:
            try await installFixture()
            let fixture = try modelFixture()
            let installedURL = try layout.installedFileURL(
                modelID: fixture.model.id,
                filename: fixture.file.filename
            )
            try Data(repeating: 0xFF, count: fixture.data.count)
                .write(to: installedURL)
            try await installFixture()
        case .cancel:
            let store = ModelInstallQueueStore(
                fileURL: layout.installQueueURL
            )
            var queue = try store.load()
            let attemptID = "soak-\(operationIndex)"
            try queue.authorize(
                artifactID: ProductionModelPolicy.requiredModelID,
                purpose: .transcription,
                action: .install,
                attemptID: attemptID,
                createdAt: "2026-07-25T00:00:00Z"
            )
            try store.save(queue)
            try queue.cancel(attemptID: attemptID)
            try store.save(queue)
        case .delete:
            try await installFixture()
            _ = try InstalledModelManager(layout: layout).remove(
                modelID: ProductionModelPolicy.requiredModelID
            )
        case .refresh:
            let snapshot = try trustedCatalogSnapshot()
            let store = try TrustedCatalogStore(
                fileURL: catalogURL,
                verifier: trustedCatalogVerifier()
            )
            try store.save(
                TrustedCatalogStoredState(
                    highestAcceptedRevision: snapshot.revision,
                    presentedSnapshot: snapshot,
                    lastSuccessfulCatalogIntegrityCheckAt: Date(
                        timeIntervalSince1970:
                        TimeInterval(operationIndex)
                    )
                )
            )
            guard try store.load().presentedSnapshot?.manifest
                == snapshot.manifest
            else {
                throw SoakError.catalogRefreshDisagreement
            }
        }
    }

    private func installFixture() async throws {
        let fixture = try modelFixture()
        _ = try await ModelInstaller(
            layout: layout,
            transport: FaultFixtureTransport(
                dataByURL: [fixture.url: fixture.data]
            ),
            availableCapacity: { _ in Int64.max / 4 }
        ).install(
            modelID: fixture.model.id,
            from: fixture.manifest
        )
    }

    private func operation(at index: Int) -> SoakOperation {
        let mixed = seed &+ UInt64(index) &* 0x9E37_79B9_7F4A_7C15
        return SoakOperation.allCases[
            Int(mixed % UInt64(SoakOperation.allCases.count))
        ]
    }

    private func loadProgress() throws -> SoakProgress {
        guard FileManager.default.fileExists(atPath: progressURL.path) else {
            return SoakProgress(
                seed: seed,
                completedOperationCount: 0,
                operationCounts: Dictionary(
                    uniqueKeysWithValues: SoakOperation.allCases.map {
                        ($0.rawValue, 0)
                    }
                )
            )
        }
        return try JSONDecoder().decode(
            SoakProgress.self,
            from: Data(contentsOf: progressURL)
        )
    }

    private func saveProgress(_ progress: SoakProgress) throws {
        try JSONEncoder().encode(progress).write(
            to: progressURL,
            options: .atomic
        )
    }

    private func writeRecovery(
        progress: SoakProgress,
        violations: [String]
    ) throws {
        let unexplained = try unexplainedManagedBytes()
        try JSONEncoder().encode(
            ModelProductionSoakRecoveryResult(
                seed: seed,
                completedOperationCount:
                progress.completedOperationCount,
                operationCounts: progress.operationCounts,
                invariantViolations: violations,
                unexplainedManagedBytes: unexplained
            )
        ).write(
            to: root.appendingPathComponent("soak-recovery.json"),
            options: .atomic
        )
    }

    private func unexplainedManagedBytes() throws -> Int64 {
        let fixture = try modelFixture()
        let receipt = try InstalledModelsStorePersistence(
            fileURL: layout.installedStoreURL
        ).load().record(forModelID: fixture.model.id)
        var known = Set([
            progressURL.standardizedFileURL.path,
            root.appendingPathComponent("soak-recovery.json")
                .standardizedFileURL.path,
            catalogURL.standardizedFileURL.path,
            layout.installQueueURL.standardizedFileURL.path,
            layout.installedStoreURL.standardizedFileURL.path,
        ])
        let expectedInstalledURL = try layout.installedFileURL(
            modelID: fixture.model.id,
            filename: fixture.file.filename
        )
        if let receipt,
           receipt.localFilesByManifestFilename[fixture.file.filename]
           == expectedInstalledURL.path
        {
            known.insert(
                expectedInstalledURL.standardizedFileURL.path
            )
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey,
            ]
        ) else {
            return 0
        }
        var bytes: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            )
            if values.isRegularFile == true,
               !known.contains(url.standardizedFileURL.path)
            {
                bytes += Int64(values.fileSize ?? 0)
            }
        }
        return bytes
    }

    private func modelFixture() throws -> (
        manifest: ModelManifest,
        model: ModelEntry,
        file: ModelFile,
        url: URL,
        data: Data
    ) {
        let directory = repositoryRoot.appendingPathComponent(
            "Tests/TextifyModelsTests/Fixtures/Models",
            isDirectory: true
        )
        let manifest = try ModelManifest.decode(
            Data(
                contentsOf: directory.appendingPathComponent(
                    "manifest.json"
                )
            )
        )
        guard let model = manifest.models.first(
            where: {
                $0.id == ProductionModelPolicy.requiredModelID
            }
        ),
            let file = model.files.first,
            let url = URL(string: file.url)
        else {
            throw SoakError.missingFixture
        }
        return try (
            manifest,
            model,
            file,
            url,
            Data(
                contentsOf: directory.appendingPathComponent("model.bin")
            )
        )
    }

    private func trustedCatalogSnapshot() throws
        -> TrustedCatalogSnapshot
    {
        let directory = repositoryRoot.appendingPathComponent(
            "Tests/TextifyModelsTests/Fixtures/Models",
            isDirectory: true
        )
        return try TrustedCatalogSnapshot(
            manifestData: Data(
                contentsOf: directory.appendingPathComponent(
                    "manifest.json"
                )
            ),
            signatureData: Data(
                contentsOf: directory.appendingPathComponent(
                    "manifest.json.sig"
                )
            ),
            verifier: trustedCatalogVerifier()
        )
    }

    private func trustedCatalogVerifier() throws -> ManifestVerifier {
        let key = try String(
            decoding: Data(
                contentsOf: repositoryRoot.appendingPathComponent(
                    "Tests/TextifyModelsTests/Fixtures/Models/manifest.fixture-public-key.base64"
                )
            ),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return ManifestVerifier(
            trustedKeys: [
                TrustedModelManifestKey(
                    keyId: "fixture-key",
                    publicKeyBase64: key
                ),
            ]
        )
    }

    private enum SoakOperation: String, CaseIterable {
        case install
        case reinstall
        case cancel
        case delete
        case refresh
    }

    private struct SoakProgress: Codable {
        let seed: UInt64
        var completedOperationCount: Int
        var operationCounts: [String: Int]
    }

    private enum SoakError: Error {
        case progressDisagreement
        case missingFixture
        case catalogRefreshDisagreement
    }
}
