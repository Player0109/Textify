import CryptoKit
import Darwin
import Foundation
import TextifyModels
import TextifySettings

public struct ModelProductionFaultExecution:
    Codable,
    Equatable,
    Sendable
{
    public let boundary: ModelWorkflowDurableBoundary
    public let fault: ModelWorkflowInjectedFault
    public let firstProcessExitStatus: Int32
    public let recoveryProcessExitStatus: Int32
    public let failpointReached: Bool
    public let injectedMutation: String
    public let forcedProcessTermination: Bool
    public let relaunchRecovered: Bool
    public let invariantViolations: [String]
    public let unexplainedManagedBytes: Int64
}

public struct ModelProductionCrashSoakReport:
    Codable,
    Equatable,
    Sendable
{
    public let seed: UInt64
    public let operationCount: Int
    public let completedOperationCount: Int
    public let operationCounts: [String: Int]
    public let scheduledCrashCount: Int
    public let forcedCrashCount: Int
    public let relaunchCount: Int
    public let invariantViolations: [String]
    public let unexplainedManagedBytes: Int64
}

public struct ModelProductionFaultCampaignReport:
    Codable,
    Equatable,
    Sendable
{
    public let schemaVersion: Int
    public let executions: [ModelProductionFaultExecution]
    public let crashSoak: ModelProductionCrashSoakReport
    public let invariantViolations: [String]
    public let unexplainedManagedBytes: Int64
}

public struct ModelProductionFaultCampaign {
    public static let forcedTerminationExitStatus: Int32 = 86

    public init() {}

    public func run(
        workerExecutableURL: URL,
        repositoryRoot: URL,
        soakOperationCount: Int = 1000,
        soakSeed: UInt64 = 24
    ) throws -> ModelProductionFaultCampaignReport {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TextifyProductionFaultCampaign-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: parent) }

        var executions: [ModelProductionFaultExecution] = []
        for boundary in ModelWorkflowDurableBoundary.allCases {
            for fault in ModelWorkflowInjectedFault.allCases {
                let root = parent.appendingPathComponent(
                    "\(boundary.rawValue)-\(fault.rawValue)",
                    isDirectory: true
                )
                try executions.append(
                    runCell(
                        boundary: boundary,
                        fault: fault,
                        root: root,
                        workerExecutableURL: workerExecutableURL,
                        repositoryRoot: repositoryRoot
                    )
                )
            }
        }

        let crashInterval = max(1, soakOperationCount / 20)
        var scheduledCrashCount = 0
        var forcedCrashCount = 0
        var relaunchCount = 0
        var soakViolations: [String] = []
        var soakUnexplainedBytes: Int64 = 0
        var completedOperationCount = 0
        var operationCounts: [String: Int] = [:]
        let soakRoot = parent.appendingPathComponent(
            "production-soak",
            isDirectory: true
        )
        for start in stride(
            from: 0,
            to: soakOperationCount,
            by: crashInterval
        ) {
            let end = min(soakOperationCount, start + crashInterval)
            scheduledCrashCount += 1
            let performStatus = try runWorker(
                executableURL: workerExecutableURL,
                repositoryRoot: repositoryRoot,
                arguments: [
                    "--fault-worker",
                    "soak",
                    soakRoot.path,
                    String(start),
                    String(end),
                    String(soakSeed),
                    repositoryRoot.path,
                ]
            )
            if performStatus == Self.forcedTerminationExitStatus {
                forcedCrashCount += 1
            } else {
                soakViolations.append(
                    "soak_process_not_terminated_\(start)_\(performStatus)"
                )
            }
            let recoveryStatus = try runWorker(
                executableURL: workerExecutableURL,
                repositoryRoot: repositoryRoot,
                arguments: [
                    "--fault-worker",
                    "soak-recover",
                    soakRoot.path,
                    String(end),
                    String(soakSeed),
                    repositoryRoot.path,
                ]
            )
            if recoveryStatus == 0 {
                relaunchCount += 1
            }
            let recovery = try JSONDecoder().decode(
                ModelProductionSoakRecoveryResult.self,
                from: Data(
                    contentsOf: soakRoot.appendingPathComponent(
                        "soak-recovery.json"
                    )
                )
            )
            completedOperationCount = recovery.completedOperationCount
            operationCounts = recovery.operationCounts
            soakViolations.append(
                contentsOf: recovery.invariantViolations
            )
            soakUnexplainedBytes = recovery.unexplainedManagedBytes
        }

        let violations = executions.flatMap(\.invariantViolations)
            + soakViolations
        let unexplainedBytes = executions.reduce(0) {
            $0 + $1.unexplainedManagedBytes
        } + soakUnexplainedBytes
        return ModelProductionFaultCampaignReport(
            schemaVersion: 1,
            executions: executions,
            crashSoak: ModelProductionCrashSoakReport(
                seed: soakSeed,
                operationCount: soakOperationCount,
                completedOperationCount: completedOperationCount,
                operationCounts: operationCounts,
                scheduledCrashCount: scheduledCrashCount,
                forcedCrashCount: forcedCrashCount,
                relaunchCount: relaunchCount,
                invariantViolations: soakViolations,
                unexplainedManagedBytes: soakUnexplainedBytes
            ),
            invariantViolations: violations,
            unexplainedManagedBytes: unexplainedBytes
        )
    }

    private func runCell(
        boundary: ModelWorkflowDurableBoundary,
        fault: ModelWorkflowInjectedFault,
        root: URL,
        workerExecutableURL: URL,
        repositoryRoot: URL
    ) throws -> ModelProductionFaultExecution {
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let performStatus = try runWorker(
            executableURL: workerExecutableURL,
            repositoryRoot: repositoryRoot,
            arguments: [
                "--fault-worker",
                "perform",
                root.path,
                boundary.rawValue,
                fault.rawValue,
                repositoryRoot.path,
            ]
        )
        let recoveryStatus = try runWorker(
            executableURL: workerExecutableURL,
            repositoryRoot: repositoryRoot,
            arguments: [
                "--fault-worker",
                "recover",
                root.path,
                boundary.rawValue,
                fault.rawValue,
                repositoryRoot.path,
            ]
        )
        let resultURL = root.appendingPathComponent("recovery-result.json")
        let recovery = try JSONDecoder().decode(
            ModelProductionFaultRecoveryResult.self,
            from: Data(contentsOf: resultURL)
        )
        let forcedTermination =
            fault == .processTermination
                && performStatus == Self.forcedTerminationExitStatus
        var violations = recovery.invariantViolations
        if fault == .processTermination, !forcedTermination {
            violations.append("process_termination_not_forced")
        }
        if fault != .processTermination, performStatus != 0 {
            violations.append("fault_worker_failed_\(performStatus)")
        }
        if recoveryStatus != 0 {
            violations.append("recovery_worker_failed_\(recoveryStatus)")
        }
        return ModelProductionFaultExecution(
            boundary: boundary,
            fault: fault,
            firstProcessExitStatus: performStatus,
            recoveryProcessExitStatus: recoveryStatus,
            failpointReached: recovery.failpointReached,
            injectedMutation: recovery.injectedMutation,
            forcedProcessTermination: forcedTermination,
            relaunchRecovered:
            recoveryStatus == 0
                && recovery.failpointReached
                && violations.isEmpty
                && recovery.unexplainedManagedBytes == 0,
            invariantViolations: violations,
            unexplainedManagedBytes: recovery.unexplainedManagedBytes
        )
    }

    private func runWorker(
        executableURL: URL,
        repositoryRoot: URL,
        arguments: [String]
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = repositoryRoot
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

public enum ModelProductionFaultWorker {
    public static func run(arguments: [String]) async throws {
        if arguments.count == 7,
           arguments[1] == "soak",
           let start = Int(arguments[3]),
           let end = Int(arguments[4]),
           let seed = UInt64(arguments[5])
        {
            try await ModelProductionSoakWorker(
                root: URL(fileURLWithPath: arguments[2], isDirectory: true),
                repositoryRoot: URL(
                    fileURLWithPath: arguments[6],
                    isDirectory: true
                ),
                seed: seed
            ).perform(start: start, end: end)
            return
        }
        if arguments.count == 6,
           arguments[1] == "soak-recover",
           let expectedCount = Int(arguments[3]),
           let seed = UInt64(arguments[4])
        {
            try await ModelProductionSoakWorker(
                root: URL(fileURLWithPath: arguments[2], isDirectory: true),
                repositoryRoot: URL(
                    fileURLWithPath: arguments[5],
                    isDirectory: true
                ),
                seed: seed
            ).recover(expectedOperationCount: expectedCount)
            return
        }
        guard arguments.count == 6,
              let mode = Mode(rawValue: arguments[1]),
              let boundary = ModelWorkflowDurableBoundary(
                  rawValue: arguments[3]
              ),
              let fault = ModelWorkflowInjectedFault(
                  rawValue: arguments[4]
              )
        else {
            throw WorkerError.invalidArguments
        }
        let root = URL(
            fileURLWithPath: arguments[2],
            isDirectory: true
        )
        let repositoryRoot = URL(
            fileURLWithPath: arguments[5],
            isDirectory: true
        )
        let worker = Worker(
            root: root,
            repositoryRoot: repositoryRoot,
            boundary: boundary,
            fault: fault
        )
        switch mode {
        case .perform:
            try await worker.perform()
        case .recover:
            try await worker.recover()
        }
    }

    private enum Mode: String {
        case perform
        case recover
    }

    private enum WorkerError: Error {
        case invalidArguments
    }
}

private struct ModelProductionFaultRecoveryResult: Codable {
    let failpointReached: Bool
    let injectedMutation: String
    let invariantViolations: [String]
    let unexplainedManagedBytes: Int64
}

private struct Worker {
    private static let artifactID = ProductionModelPolicy.requiredModelID
    private static let attemptID = "fault-attempt"
    private static let seedAttemptID = "fault-seed-attempt"

    let root: URL
    let repositoryRoot: URL
    let boundary: ModelWorkflowDurableBoundary
    let fault: ModelWorkflowInjectedFault

    private var layout: ModelStorageLayout {
        ModelStorageLayout(
            rootDirectory: root.appendingPathComponent(
                "Models",
                isDirectory: true
            )
        )
    }

    private var settingsURL: URL {
        root.appendingPathComponent("settings.json")
    }

    private var evidenceDirectory: URL {
        root.appendingPathComponent(
            ".fault-evidence",
            isDirectory: true
        )
    }

    private var markerURL: URL {
        evidenceDirectory.appendingPathComponent("failpoint.json")
    }

    private var mutationURL: URL {
        evidenceDirectory.appendingPathComponent("mutation-applied.json")
    }

    func perform() async throws {
        try FileManager.default.createDirectory(
            at: evidenceDirectory,
            withIntermediateDirectories: true
        )
        try await seedFaultTargets()
        do {
            switch boundary {
            case .queueAuthorizationPersisted:
                try persistQueueAuthorization(observer: observer())
            case .queueAttemptStartedPersisted:
                try persistQueueStart(observer: observer())
            case .partialMetadataPersisted:
                try persistPartialMetadata(observer: observer())
            case .installationStaged,
                 .installationReceiptPersisted:
                _ = try await install(observer: observer())
            case .activationPrepared,
                 .activationPreferencePersisted:
                try prepareActivation(observer: observer())
            case .revocationRestorationPersisted:
                try persistRevocation(observer: observer())
            case .restorationIntegrityAcknowledged:
                try persistRestorationAcknowledgment(
                    observer: observer()
                )
            case .deletionRenamedPending,
                 .deletionBytesRemoved,
                 .deletionReceiptRemoved:
                _ = try InstalledModelManager(
                    layout: layout,
                    durabilityObserver: observer()
                ).remove(modelID: Self.artifactID)
            case .reconciliationReceiptPersisted:
                try persistReconciliation(observer: observer())
            }
        } catch {
            guard FileManager.default.fileExists(atPath: markerURL.path) else {
                throw error
            }
        }
    }

    func recover() async throws {
        var violations: [String] = []
        let reached = FileManager.default.fileExists(atPath: markerURL.path)
        if !reached {
            violations.append("failpoint_not_reached")
        }
        if fault != .processTermination,
           !FileManager.default.fileExists(atPath: mutationURL.path)
        {
            violations.append("fault_mutation_not_applied")
        }
        if fault == .revocation {
            try recoverRevocation(violations: &violations)
        }

        switch boundary {
        case .queueAuthorizationPersisted,
             .queueAttemptStartedPersisted,
             .partialMetadataPersisted:
            try recoverQueueAndPartial(violations: &violations)
        case .installationStaged,
             .installationReceiptPersisted:
            if fault == .revocation {
                if boundary == .installationStaged {
                    let installed = try layout.installedModelDirectory(
                        modelID: Self.artifactID
                    )
                    try? FileManager.default.removeItem(at: installed)
                }
            } else {
                do {
                    _ = try await install(observer: .none)
                } catch {
                    violations.append("installation_unrecoverable")
                }
            }
        case .activationPrepared,
             .activationPreferencePersisted:
            try recoverActivation(violations: &violations)
        case .revocationRestorationPersisted:
            if fault != .revocation {
                try recoverRevocation(violations: &violations)
            }
        case .restorationIntegrityAcknowledged:
            break
        case .deletionRenamedPending,
             .deletionBytesRemoved,
             .deletionReceiptRemoved:
            try recoverDeletion(violations: &violations)
        case .reconciliationReceiptPersisted:
            if try loadInstalledStore()
                .record(forModelID: Self.artifactID) == nil
            {
                violations.append("reconciliation_receipt_lost")
            }
        }
        try recoverFaultTargets(violations: &violations)

        if boundary != .deletionRenamedPending,
           boundary != .deletionBytesRemoved,
           boundary != .deletionReceiptRemoved,
           try loadInstalledStore()
           .record(forModelID: Self.artifactID) != nil,
           !installedPayloadIsValid()
        {
            do {
                _ = try await install(observer: .none)
            } catch {
                violations.append("installed_integrity_unrecoverable")
            }
        }
        if boundary == .restorationIntegrityAcknowledged {
            try recoverRestorationAcknowledgment(
                violations: &violations
            )
        }
        try auditActivation(violations: &violations)
        try auditReceiptOwnership(violations: &violations)
        let unexplained = try unexplainedManagedBytes()
        let result = ModelProductionFaultRecoveryResult(
            failpointReached: reached,
            injectedMutation: recordedMutation(),
            invariantViolations: Array(Set(violations)).sorted(),
            unexplainedManagedBytes: unexplained
        )
        try JSONEncoder().encode(result).write(
            to: root.appendingPathComponent("recovery-result.json"),
            options: .atomic
        )
    }

    private func seedFaultTargets() async throws {
        if boundary != .installationStaged,
           boundary != .installationReceiptPersisted
        {
            _ = try await install(observer: .none)
        }
        try persistSeedQueueAuthorization()
        try seedPartial(observer: .none)
        let snapshot = try trustedCatalogSnapshot()
        try trustedCatalogStore().save(
            TrustedCatalogStoredState(
                highestAcceptedRevision: snapshot.revision,
                presentedSnapshot: snapshot
            )
        )
        var preferences = AppPreferences.defaults
        if boundary != .deletionRenamedPending,
           boundary != .deletionBytesRemoved,
           boundary != .deletionReceiptRemoved,
           try loadInstalledStore()
           .record(forModelID: Self.artifactID) != nil
        {
            preferences.activeModelID = Self.artifactID
        }
        SettingsStore(storage: .file(settingsURL)).save(preferences)
    }

    private func observer() -> ModelWorkflowDurabilityObserver {
        ModelWorkflowDurabilityObserver { observed, _ in
            guard observed == boundary else {
                return
            }
            try writeMarker()
            try injectFault()
        }
    }

    private func writeMarker() throws {
        let marker = [
            "boundary": boundary.rawValue,
            "fault": fault.rawValue,
        ]
        try JSONEncoder().encode(marker).write(
            to: markerURL,
            options: .atomic
        )
    }

    private func injectFault() throws {
        switch fault {
        case .processTermination:
            Darwin._exit(
                ModelProductionFaultCampaign
                    .forcedTerminationExitStatus
            )
        case .diskFull:
            try recordMutationApplied()
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(ENOSPC)
            )
        case .permissionFailure:
            try recordMutationApplied()
            throw CocoaError(.fileWriteNoPermission)
        case .renameFailure:
            try recordMutationApplied()
            throw CocoaError(.fileWriteFileExists)
        case .checksumMismatch:
            try mutateManagedPayload { data in
                guard !data.isEmpty else {
                    return Data([0xFF])
                }
                var changed = data
                changed[changed.startIndex] ^= 0xFF
                return changed
            }
            try recordMutationApplied()
        case .truncation:
            try mutateManagedPayload {
                Data($0.prefix(max(0, $0.count / 2)))
            }
            try recordMutationApplied()
        case .missingFiles:
            guard let payloadURL = existingPayloadURL() else {
                throw InjectedMutationFault.notApplied
            }
            try FileManager.default.removeItem(at: payloadURL)
            try recordMutationApplied()
        case .extraFiles:
            let directory = layout.downloadsDirectory
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try Data("extra".utf8).write(
                to: directory.appendingPathComponent(
                    ".\(Self.artifactID).unverified-extra"
                )
            )
            try recordMutationApplied()
        case .catalogReplacement:
            let state = try TrustedCatalogStoredState(
                highestAcceptedRevision: trustedCatalogSnapshot().revision,
                presentedSnapshot: trustedCatalogSnapshot(),
                securityIssue: TrustedCatalogSecurityIssue(
                    reason: .schemaValidation,
                    candidateRevision: "2026-07-26T00:00:00Z",
                    highestAcceptedRevision:
                    trustedCatalogSnapshot().revision
                )
            )
            try trustedCatalogStore().save(state)
            try recordMutationApplied()
        case .incompatibility:
            let compatible = try ModelCatalogCompatibilityResolver(
                context: ModelCatalogCompatibilityContext(
                    appVersion: "1.1.0",
                    macOSVersion: "14.0.0",
                    architecture: .arm64,
                    physicalMemoryBytes: Int64.max
                )
            ).compatibility(
                for: Self.artifactID,
                in: fixture().manifest
            )
            let incompatible = try ModelCatalogCompatibilityResolver(
                context: ModelCatalogCompatibilityContext(
                    appVersion: "0.0.1",
                    macOSVersion: "14.0.0",
                    architecture: .arm64,
                    physicalMemoryBytes: Int64.max
                )
            ).compatibility(
                for: Self.artifactID,
                in: fixture().manifest
            )
            guard compatible.allowsModelOperations,
                  !incompatible.allowsModelOperations
            else {
                throw InjectedMutationFault.notApplied
            }
            var preferences = SettingsStore(
                storage: .file(settingsURL)
            ).load()
            preferences.activeModelID = nil
            SettingsStore(storage: .file(settingsURL)).save(preferences)
            try recordMutationApplied(
                "compatibility_resolver:compatible->requires_app_update"
            )
        case .revocation:
            try persistRevocation(observer: .none)
            try recordMutationApplied()
        }
        throw InjectedMutationFault.injected
    }

    private func recordMutationApplied(
        _ evidence: String? = nil
    ) throws {
        try Data((evidence ?? injectedMutation()).utf8).write(
            to: mutationURL,
            options: .atomic
        )
    }

    private func persistQueueAuthorization(
        observer: ModelWorkflowDurabilityObserver
    ) throws {
        var queue = ModelInstallQueue()
        try queue.authorize(
            artifactID: Self.artifactID,
            purpose: .transcription,
            action: .install,
            attemptID: Self.attemptID,
            createdAt: "2026-07-25T00:00:00Z"
        )
        try ModelInstallQueueStore(
            fileURL: layout.installQueueURL,
            durabilityObserver: observer
        ).save(queue)
    }

    private func persistSeedQueueAuthorization() throws {
        var queue = ModelInstallQueue()
        try queue.authorize(
            artifactID: Self.artifactID,
            purpose: .transcription,
            action: .install,
            attemptID: Self.seedAttemptID,
            createdAt: "2026-07-25T00:00:00Z"
        )
        try ModelInstallQueueStore(
            fileURL: layout.installQueueURL
        ).save(queue)
    }

    private func persistQueueStart(
        observer: ModelWorkflowDurabilityObserver
    ) throws {
        try persistQueueAuthorization(observer: .none)
        let store = ModelInstallQueueStore(
            fileURL: layout.installQueueURL,
            durabilityObserver: observer
        )
        var queue = try store.load()
        try queue.transition(
            attemptID: Self.attemptID,
            to: DownloadState(
                modelID: Self.artifactID,
                phase: .checkingSpace,
                message: "Checking space",
                attemptID: Self.attemptID
            )
        )
        try store.save(queue)
    }

    private func persistPartialMetadata(
        observer: ModelWorkflowDurabilityObserver
    ) throws {
        try persistQueueAuthorization(observer: .none)
        try seedPartial(observer: observer)
    }

    private func seedPartial(
        observer: ModelWorkflowDurabilityObserver
    ) throws {
        let fixture = try fixture()
        let file = fixture.file
        try FileManager.default.createDirectory(
            at: layout.downloadsDirectory,
            withIntermediateDirectories: true
        )
        let partialURL = try layout.temporaryDownloadURL(
            modelID: Self.artifactID,
            filename: file.filename
        )
        let partial = Data(fixture.data.prefix(fixture.data.count / 2))
        try partial.write(to: partialURL)
        let metadata = DownloadResumeMetadata(
            modelID: Self.artifactID,
            url: file.url,
            expectedSize: file.sizeBytes,
            sha256: file.sha256,
            eTag: "\"fault-fixture\"",
            lastModified: nil,
            bytesDownloaded: Int64(partial.count)
        )
        try DownloadResumeMetadataPersistence(
            fileURL: layout.downloadResumeMetadataURL(
                modelID: Self.artifactID,
                filename: file.filename
            ),
            durabilityObserver: observer
        ).save(metadata)
    }

    private func install(
        observer: ModelWorkflowDurabilityObserver
    ) async throws -> InstalledModelRecord {
        let fixture = try fixture()
        return try await ModelInstaller(
            layout: layout,
            transport: FaultFixtureTransport(
                dataByURL: [fixture.url: fixture.data]
            ),
            durabilityObserver: observer,
            availableCapacity: { _ in Int64.max / 4 }
        ).install(
            modelID: Self.artifactID,
            from: fixture.manifest
        )
    }

    private func prepareActivation(
        observer: ModelWorkflowDurabilityObserver
    ) throws {
        let store = SettingsStore(storage: .file(settingsURL))
        store.save(.defaults)
        let persistence = PreparedModelActivationPersistence(
            store: store,
            durabilityObserver: observer
        )
        try persistence.recordPrepared(modelID: Self.artifactID)
        var preferences = store.load()
        preferences.activeModelID = Self.artifactID
        try persistence.persistSelection(
            preferences,
            modelID: Self.artifactID
        )
    }

    private func persistRevocation(
        observer: ModelWorkflowDurabilityObserver
    ) throws {
        var preferences = AppPreferences.defaults
        preferences.activeModelID = Self.artifactID
        SettingsStore(storage: .file(settingsURL)).save(preferences)
        let privateKey = Curve25519.Signing.PrivateKey()
        let trustedKey = TrustedModelManifestKey(
            keyId: "fault-key",
            publicKeyBase64: privateKey.publicKey.rawRepresentation
                .base64EncodedString()
        )
        let revocationData = Data(
            """
            {"revocationVersion":1,"generatedAt":"2026-07-25T00:00:00Z","records":[{"recordID":"fault-revocation","exactArtifactID":"\(Self.artifactID)","contentDigest":null}]}
            """.utf8
        )
        let signature = try revocationSignature(
            data: revocationData,
            privateKey: privateKey
        )
        let verifier = ModelRevocationVerifier(
            trustedKeys: [trustedKey]
        )
        let snapshot = try TrustedModelRevocationSnapshot(
            revocationData: revocationData,
            signatureData: signature,
            verifier: verifier
        )
        let state = try TrustedModelRevocationState().accepting(
            snapshot
        )
        try privateKey.publicKey.rawRepresentation.write(
            to: evidenceDirectory.appendingPathComponent(
                "revocation-public-key"
            ),
            options: .atomic
        )
        try TrustedModelRevocationStore(
            fileURL: root.appendingPathComponent("revocations.json"),
            verifier: verifier,
            catalogVerifier: ManifestVerifier(
                trustedKeys: [trustedKey]
            ),
            durabilityObserver: observer
        ).save(state)
    }

    private func persistRestorationAcknowledgment(
        observer: ModelWorkflowDurabilityObserver
    ) throws {
        let record = try requiredInstalledRecord()
        let acknowledged = InstalledModelRecord(
            model: record.model,
            installedAt: record.installedAt,
            localFilesByManifestFilename:
            record.localFilesByManifestFilename,
            storageModelID: record.storageModelID,
            identityHistory: record.identityHistory,
            verifiedRestorationIDs: ["restore-a"]
        )
        try InstalledModelsStorePersistence(
            fileURL: layout.installedStoreURL,
            durabilityObserver: observer
        ).persistRestorationAcknowledgment(
            InstalledModelsStore(records: [acknowledged]),
            artifactID: Self.artifactID
        )
    }

    private func persistReconciliation(
        observer: ModelWorkflowDurabilityObserver
    ) throws {
        let record = try requiredInstalledRecord()
        try InstalledModelsStorePersistence(
            fileURL: layout.installedStoreURL,
            durabilityObserver: observer
        ).persistReconciliation(
            InstalledModelsStore(records: [record])
        )
    }

    private func recoverQueueAndPartial(
        violations: inout [String]
    ) throws {
        let queue = try ModelInstallQueueStore(
            fileURL: layout.installQueueURL
        ).loadForRelaunch()
        guard queue.attempt(id: Self.attemptID) != nil else {
            violations.append("queue_attempt_lost")
            return
        }
        guard boundary == .partialMetadataPersisted else {
            return
        }
        let fixture = try fixture()
        let partialURL = try layout.temporaryDownloadURL(
            modelID: Self.artifactID,
            filename: fixture.file.filename
        )
        let metadataURL = try layout.downloadResumeMetadataURL(
            modelID: Self.artifactID,
            filename: fixture.file.filename
        )
        let metadata = try? JSONDecoder().decode(
            DownloadResumeMetadata.self,
            from: Data(contentsOf: metadataURL)
        )
        let size = (try? Data(contentsOf: partialURL).count) ?? -1
        let agrees =
            metadata != nil
                && metadata?.bytesDownloaded == Int64(size)
                && metadata?.modelID == Self.artifactID
        if !agrees {
            try? FileManager.default.removeItem(at: partialURL)
            try? FileManager.default.removeItem(at: metadataURL)
        }
    }

    private func recoverFaultTargets(
        violations: inout [String]
    ) throws {
        let extraURL = layout.downloadsDirectory.appendingPathComponent(
            ".\(Self.artifactID).unverified-extra"
        )
        if FileManager.default.fileExists(atPath: extraURL.path) {
            try? FileManager.default.removeItem(at: extraURL)
        }

        let fixture = try fixture()
        let metadataURL = try layout.downloadResumeMetadataURL(
            modelID: Self.artifactID,
            filename: fixture.file.filename
        )
        if FileManager.default.fileExists(atPath: metadataURL.path),
           ModelDownloadStorageValidation.validatedPartialURL(
               for: metadataURL,
               expectedModelID: Self.artifactID,
               expectedFiles: [fixture.file]
           ) == nil
        {
            let partialURL = try layout.temporaryDownloadURL(
                modelID: Self.artifactID,
                filename: fixture.file.filename
            )
            try? FileManager.default.removeItem(at: partialURL)
            try? FileManager.default.removeItem(at: metadataURL)
        }

        if fault == .catalogReplacement {
            let catalog = try trustedCatalogStore().load()
            if catalog.presentedSnapshot?.manifest.models.first(
                where: { $0.id == Self.artifactID }
            ) == nil {
                violations.append("trusted_catalog_replaced")
            }
            if catalog.securityIssue == nil {
                violations.append("catalog_replacement_not_recorded")
            }
        }
        if fault == .incompatibility,
           SettingsStore(storage: .file(settingsURL))
           .load().activeModelID != nil
        {
            violations.append("incompatible_activation_retained")
        }
    }

    private func recoverActivation(
        violations: inout [String]
    ) throws {
        let store = SettingsStore(storage: .file(settingsURL))
        var preferences = store.load()
        let mustDisable =
            fault == .revocation
                || fault == .incompatibility
                || !installedPayloadIsValid()
        if mustDisable {
            preferences.activeModelID = nil
            store.save(preferences)
        }
        if boundary == .activationPrepared,
           preferences.activeModelID != nil
        {
            violations.append("activation_committed_before_preparation_boundary")
        }
    }

    private func recoverRestorationAcknowledgment(
        violations: inout [String]
    ) throws {
        guard let record = try loadInstalledStore()
            .record(forModelID: Self.artifactID)
        else {
            violations.append("restoration_acknowledgment_receipt_lost")
            return
        }
        if record.verifiedRestorationIDs != ["restore-a"] {
            let acknowledged = InstalledModelRecord(
                model: record.model,
                installedAt: record.installedAt,
                localFilesByManifestFilename:
                record.localFilesByManifestFilename,
                storageModelID: record.storageModelID,
                identityHistory: record.identityHistory,
                verifiedRestorationIDs: ["restore-a"]
            )
            try InstalledModelsStorePersistence(
                fileURL: layout.installedStoreURL
            ).persistRestorationAcknowledgment(
                InstalledModelsStore(records: [acknowledged]),
                artifactID: Self.artifactID
            )
        }
        if try loadInstalledStore()
            .record(forModelID: Self.artifactID)?
            .verifiedRestorationIDs != ["restore-a"]
        {
            violations.append("restoration_acknowledgment_lost")
        }
    }

    private func recoverRevocation(
        violations: inout [String]
    ) throws {
        let keyURL = evidenceDirectory.appendingPathComponent(
            "revocation-public-key"
        )
        guard let publicKeyData = try? Data(contentsOf: keyURL) else {
            violations.append("revocation_key_evidence_lost")
            return
        }
        let trustedKey = TrustedModelManifestKey(
            keyId: "fault-key",
            publicKeyBase64: publicKeyData.base64EncodedString()
        )
        let store = TrustedModelRevocationStore(
            fileURL: root.appendingPathComponent("revocations.json"),
            verifier: ModelRevocationVerifier(
                trustedKeys: [trustedKey]
            ),
            catalogVerifier: ManifestVerifier(
                trustedKeys: [trustedKey]
            )
        )
        guard (try? store.load().overlay.isRevoked(
            artifactID: Self.artifactID,
            trustedManifest: nil
        )) == true else {
            violations.append("revocation_state_lost")
            return
        }
        let settings = SettingsStore(storage: .file(settingsURL))
        var preferences = settings.load()
        preferences.activeModelID = nil
        settings.save(preferences)
    }

    private func recoverDeletion(
        violations: inout [String]
    ) throws {
        if try loadInstalledStore()
            .record(forModelID: Self.artifactID) != nil
        {
            do {
                _ = try InstalledModelManager(layout: layout).remove(
                    modelID: Self.artifactID
                )
            } catch {
                violations.append("deletion_unrecoverable")
            }
        }
        if try loadInstalledStore()
            .record(forModelID: Self.artifactID) != nil
        {
            violations.append("deletion_receipt_retained_after_recovery")
        }
        let installed = try layout.installedModelDirectory(
            modelID: Self.artifactID
        )
        let pending = try layout.pendingRemovalDirectory(
            modelID: Self.artifactID
        )
        if FileManager.default.fileExists(atPath: installed.path)
            || FileManager.default.fileExists(atPath: pending.path)
        {
            violations.append("unconfirmed_deletion_bytes")
        }
    }

    private func auditActivation(
        violations: inout [String]
    ) throws {
        let preferences = SettingsStore(
            storage: .file(settingsURL)
        ).load()
        guard let active = preferences.activeModelID else {
            return
        }
        guard active == Self.artifactID,
              try loadInstalledStore().record(forModelID: active) != nil,
              installedPayloadIsValid(),
              fault != .revocation,
              fault != .incompatibility
        else {
            violations.append("wrong_activation")
            return
        }
    }

    private func auditReceiptOwnership(
        violations: inout [String]
    ) throws {
        let store = try loadInstalledStore()
        let installedRoot = layout.installedModelsDirectory
        guard FileManager.default.fileExists(atPath: installedRoot.path)
        else {
            return
        }
        let owned = Set(store.records.map(\.storageModelID))
        let declaredFiles = Set(
            store.records.flatMap {
                $0.localFilesByManifestFilename.values.map {
                    URL(fileURLWithPath: $0)
                        .standardizedFileURL.path
                }
            }
        )
        let children = try FileManager.default.contentsOfDirectory(
            at: installedRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        for child in children {
            let name = child.lastPathComponent
            if name.hasPrefix(".") {
                continue
            }
            if !owned.contains(name) {
                violations.append("managed_bytes_without_receipt")
            }
        }
        guard let enumerator = FileManager.default.enumerator(
            at: installedRoot,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return
        }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey]
            )
            if values.isRegularFile == true,
               !declaredFiles.contains(url.standardizedFileURL.path)
            {
                violations.append("installed_file_without_receipt_metadata")
            }
        }
        for record in store.records {
            for file in record.model.files {
                guard let path =
                    record.localFilesByManifestFilename[file.filename],
                    let data = try? Data(
                        contentsOf: URL(fileURLWithPath: path)
                    ),
                    Int64(data.count) == file.sizeBytes,
                    SHA256.hash(data: data).map({
                        String(format: "%02x", $0)
                    }).joined() == file.sha256.lowercased()
                else {
                    violations.append("receipt_payload_disagreement")
                    continue
                }
            }
        }
    }

    private func unexplainedManagedBytes() throws -> Int64 {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return 0
        }
        let store = try loadInstalledStore()
        let declaredInstalledPaths = Set(
            store.records.flatMap {
                $0.localFilesByManifestFilename.values.map {
                    URL(fileURLWithPath: $0)
                        .standardizedFileURL.path
                }
            }
        )
        let pendingRoots = store.records.compactMap {
            try? layout.pendingRemovalDirectory(
                modelID: $0.storageModelID
            ).standardizedFileURL.path
        }
        let queue = (try? ModelInstallQueueStore(
            fileURL: layout.installQueueURL
        ).load()) ?? ModelInstallQueue()
        let queuedIDs = Set(queue.attempts.map(\.artifactID))
        var queuedDataPaths = Set<String>()
        if let fixture = try? fixture() {
            for queuedID in queuedIDs {
                if let partial = try? layout.temporaryDownloadURL(
                    modelID: queuedID,
                    filename: fixture.file.filename
                ) {
                    queuedDataPaths.insert(
                        partial.standardizedFileURL.path
                    )
                }
                if let metadata = try? layout.downloadResumeMetadataURL(
                    modelID: queuedID,
                    filename: fixture.file.filename
                ) {
                    queuedDataPaths.insert(
                        metadata.standardizedFileURL.path
                    )
                }
            }
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
        var unexplained: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            )
            guard values.isRegularFile == true else {
                continue
            }
            let path = url.standardizedFileURL.path
            if path.hasPrefix(evidenceDirectory.standardizedFileURL.path)
                || path == settingsURL.standardizedFileURL.path
                || path == root.appendingPathComponent(
                    "revocations.json"
                ).standardizedFileURL.path
                || path == root.appendingPathComponent(
                    "trusted-catalog.json"
                ).standardizedFileURL.path
                || path == root.appendingPathComponent(
                    "recovery-result.json"
                ).standardizedFileURL.path
                || path == layout.installedStoreURL.standardizedFileURL.path
                || path == layout.installQueueURL.standardizedFileURL.path
            {
                continue
            }
            if declaredInstalledPaths.contains(path)
                || pendingRoots.contains(where: {
                    path == $0 || path.hasPrefix($0 + "/")
                })
            {
                continue
            }
            if queuedDataPaths.contains(path) {
                continue
            }
            unexplained += Int64(values.fileSize ?? 0)
        }
        return unexplained
    }

    private func loadInstalledStore() throws -> InstalledModelsStore {
        try InstalledModelsStorePersistence(
            fileURL: layout.installedStoreURL
        ).load()
    }

    private func requiredInstalledRecord() throws -> InstalledModelRecord {
        guard let record = try loadInstalledStore()
            .record(forModelID: Self.artifactID)
        else {
            throw FixtureError.missingInstalledRecord
        }
        return record
    }

    private func trustedCatalogStore() throws -> TrustedCatalogStore {
        try TrustedCatalogStore(
            fileURL: root.appendingPathComponent(
                "trusted-catalog.json"
            ),
            verifier: trustedCatalogVerifier()
        )
    }

    private func trustedCatalogSnapshot() throws -> TrustedCatalogSnapshot {
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

    private func injectedMutation() -> String {
        switch fault {
        case .processTermination:
            "forced_process_exit"
        case .diskFull:
            "enospc_at_durable_boundary"
        case .permissionFailure:
            "permission_error_at_durable_boundary"
        case .renameFailure:
            "rename_error_at_durable_boundary"
        case .checksumMismatch:
            "managed_payload_checksum_changed"
        case .truncation:
            "managed_payload_truncated"
        case .missingFiles:
            "managed_payload_removed"
        case .extraFiles:
            "unverified_managed_file_created"
        case .catalogReplacement:
            "trusted_catalog_replacement_rejected"
        case .incompatibility:
            "production_compatibility_gate_failed_closed"
        case .revocation:
            "signed_revocation_persisted"
        }
    }

    private func recordedMutation() -> String {
        if fault == .processTermination {
            return injectedMutation()
        }
        guard let data = try? Data(contentsOf: mutationURL) else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func existingPayloadURL() -> URL? {
        let fixture = try? fixture()
        if let file = fixture?.file,
           let installed = try? layout.installedFileURL(
               modelID: Self.artifactID,
               filename: file.filename
           ),
           FileManager.default.fileExists(atPath: installed.path)
        {
            return installed
        }
        if let file = fixture?.file,
           let partial = try? layout.temporaryDownloadURL(
               modelID: Self.artifactID,
               filename: file.filename
           ),
           FileManager.default.fileExists(atPath: partial.path)
        {
            return partial
        }
        return nil
    }

    private func mutateManagedPayload(
        _ mutation: (Data) -> Data
    ) throws {
        guard let url = existingPayloadURL() else {
            throw InjectedMutationFault.notApplied
        }
        try mutation(Data(contentsOf: url)).write(to: url)
    }

    private func installedPayloadIsValid() -> Bool {
        guard let fixture = try? fixture(),
              let url = try? layout.installedFileURL(
                  modelID: Self.artifactID,
                  filename: fixture.file.filename
              ),
              let data = try? Data(contentsOf: url)
        else {
            return false
        }
        return data == fixture.data
    }

    private func fixture() throws -> (
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
            where: { $0.id == Self.artifactID }
        ),
            let file = model.files.first,
            let url = URL(string: file.url)
        else {
            throw FixtureError.missingModel
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

    private func revocationSignature(
        data: Data,
        privateKey: Curve25519.Signing.PrivateKey
    ) throws -> Data {
        let digest = SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
        let contentType =
            "application/vnd.textify.model-revocations+json;version=1"
        let payload = """
        TEXTIFY-MODEL-REVOCATIONS-SIGNATURE-V1
        signatureVersion=1
        signatureType=io.github.Player0109.Textify.model-revocations
        algorithm=Ed25519
        keyId=fault-key
        revocationFile=revocations.json
        contentType=\(contentType)
        contentSHA256=\(digest)

        """
        let signature = try privateKey.signature(
            for: Data(payload.utf8)
        ).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return try JSONSerialization.data(
            withJSONObject: [
                "signatureVersion": 1,
                "signatureType":
                    "io.github.Player0109.Textify.model-revocations",
                "keyId": "fault-key",
                "algorithm": "Ed25519",
                "revocationFile": "revocations.json",
                "contentType": contentType,
                "contentSHA256": digest,
                "signature": signature,
            ],
            options: [.sortedKeys]
        )
    }

    private enum FixtureError: Error {
        case missingModel
        case missingInstalledRecord
    }

    private enum InjectedMutationFault: Error {
        case injected
        case notApplied
    }
}

final class FaultFixtureTransport:
    DownloadTransport,
    @unchecked Sendable
{
    private let dataByURL: [URL: Data]

    init(dataByURL: [URL: Data]) {
        self.dataByURL = dataByURL
    }

    func fetch(_ request: URLRequest) async throws -> DownloadResponse {
        guard let url = request.url,
              let data = dataByURL[url]
        else {
            throw URLError(.resourceUnavailable)
        }
        return DownloadResponse(data: data)
    }

    func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL
    ) async throws -> DownloadFileResponse {
        let response = try await fetch(request)
        try response.data.write(to: temporaryURL)
        return DownloadFileResponse(fileURL: temporaryURL)
    }

    func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL,
        maximumBytes _: Int64,
        admissionCheck: @escaping @Sendable (
            DownloadFileProgress
        ) throws -> Void,
        progress: @escaping @Sendable (
            DownloadFileProgress
        ) -> Void
    ) async throws -> DownloadFileResponse {
        let response = try await downloadFile(
            request,
            to: temporaryURL
        )
        let byteCount = try Int64(
            Data(contentsOf: response.fileURL).count
        )
        let final = DownloadFileProgress(
            bytesDownloaded: byteCount,
            totalBytes: byteCount
        )
        try admissionCheck(final)
        progress(final)
        return response
    }
}
