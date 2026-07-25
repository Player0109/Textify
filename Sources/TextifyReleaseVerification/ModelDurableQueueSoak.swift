import Foundation
import TextifyModels

struct ModelDurableQueueRecoveryProbeResult {
    let restartRecoveredQueue: Bool
    let offlineQueueStayedDurable: Bool
}

struct ModelDurableQueueRecoveryProbe {
    func run(root: URL) throws -> ModelDurableQueueRecoveryProbeResult {
        let store = ModelInstallQueueStore(
            fileURL: root.appendingPathComponent("install-queue.json")
        )
        var queue = ModelInstallQueue()
        let attemptID = "offline-attempt"
        try queue.authorize(
            artifactID: "fixture-artifact",
            purpose: .transcription,
            action: .install,
            attemptID: attemptID,
            createdAt: "2026-07-25T00:00:00Z"
        )
        try queue.transition(
            attemptID: attemptID,
            to: DownloadState(
                modelID: "fixture-artifact",
                phase: .waitingForNetwork,
                message: "Waiting for network.",
                attemptID: attemptID
            )
        )
        try store.save(queue)
        let offlineQueueStayedDurable =
            try store.load().attempt(id: attemptID)?.state.phase
                == .waitingForNetwork

        try queue.transition(
            attemptID: attemptID,
            to: DownloadState(
                modelID: "fixture-artifact",
                phase: .queued,
                message: "Queued",
                attemptID: attemptID
            )
        )
        try queue.transition(
            attemptID: attemptID,
            to: DownloadState(
                modelID: "fixture-artifact",
                phase: .checkingSpace,
                message: "Checking space",
                attemptID: attemptID
            )
        )
        try store.save(queue)
        let restartRecoveredQueue =
            try store.loadForRelaunch().attempt(id: attemptID)?.state.phase
                == .queued
        return ModelDurableQueueRecoveryProbeResult(
            restartRecoveredQueue: restartRecoveredQueue,
            offlineQueueStayedDurable: offlineQueueStayedDurable
        )
    }
}

public struct ModelDurableQueueSoakReport:
    Codable,
    Equatable,
    Sendable
{
    public let operationCount: Int
    public let relaunchCount: Int
    public let lostAttemptCount: Int
    public let partialCleanupMismatchCount: Int
    public let unexplainedManagedBytes: Int64
}

struct ModelDurableQueueSoak {
    func run(operationCount: Int) throws -> ModelDurableQueueSoakReport {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TextifyDurableQueueSoak-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = ModelStorageLayout(rootDirectory: root)
        let store = ModelInstallQueueStore(fileURL: layout.installQueueURL)
        var relaunchCount = 0
        var lostAttemptCount = 0
        var partialCleanupMismatchCount = 0
        let recoveryProbe = try ModelDurableQueueRecoveryProbe().run(
            root: root
        )
        if !recoveryProbe.restartRecoveredQueue
            || !recoveryProbe.offlineQueueStayedDurable
        {
            lostAttemptCount += 1
        }

        for index in 0..<operationCount {
            var queue = ModelInstallQueue()
            let attemptID = "soak-attempt-\(index)"
            let artifactID = "soak-artifact-\(index)"
            try queue.authorize(
                artifactID: artifactID,
                purpose: .transcription,
                action: .install,
                attemptID: attemptID,
                createdAt: "2026-07-25T00:00:00Z"
            )
            try store.save(queue)
            queue = try ModelInstallQueueStore(
                fileURL: layout.installQueueURL
            ).load()
            relaunchCount += 1
            if queue.attempt(id: attemptID) == nil {
                lostAttemptCount += 1
            }

            try queue.transition(
                attemptID: attemptID,
                to: DownloadState(
                    modelID: artifactID,
                    phase: .checkingSpace,
                    message: "Checking space",
                    attemptID: attemptID
                )
            )
            try store.save(queue)
            queue = try ModelInstallQueueStore(
                fileURL: layout.installQueueURL
            ).loadForRelaunch()
            relaunchCount += 1
            if queue.attempt(id: attemptID)?.state.phase != .queued {
                lostAttemptCount += 1
            }

            if index.isMultiple(of: 10) {
                let filename = "model.bin"
                let partialURL = try layout.temporaryDownloadURL(
                    modelID: artifactID,
                    filename: filename
                )
                let metadataURL = try layout.downloadResumeMetadataURL(
                    modelID: artifactID,
                    filename: filename
                )
                try FileManager.default.createDirectory(
                    at: layout.downloadsDirectory,
                    withIntermediateDirectories: true
                )
                try Data("validated-prefix".utf8).write(to: partialURL)
                let metadata = DownloadResumeMetadata(
                    modelID: artifactID,
                    url: "https://example.com/model.bin",
                    expectedSize: 32,
                    sha256: String(repeating: "a", count: 64),
                    eTag: "\"soak\"",
                    lastModified: nil,
                    bytesDownloaded: 16
                )
                try JSONEncoder().encode(metadata).write(
                    to: metadataURL,
                    options: [.atomic]
                )
                try ModelInstallRetainedDataRemover(layout: layout).remove(
                    modelID: artifactID,
                    filenames: [filename]
                )
                if FileManager.default.fileExists(atPath: partialURL.path)
                    || FileManager.default.fileExists(
                        atPath: metadataURL.path
                    )
                {
                    partialCleanupMismatchCount += 1
                }
            }

            try queue.cancel(attemptID: attemptID)
            try store.save(queue)
            queue = try ModelInstallQueueStore(
                fileURL: layout.installQueueURL
            ).load()
            relaunchCount += 1
            if queue.attempt(id: attemptID)?.state.phase != .cancelled {
                lostAttemptCount += 1
            }
        }

        let unexplainedManagedBytes = try unexplainedBytes(
            in: root,
            allowedPaths: [
                layout.installQueueURL.standardizedFileURL.path,
            ]
        )
        return ModelDurableQueueSoakReport(
            operationCount: operationCount,
            relaunchCount: relaunchCount,
            lostAttemptCount: lostAttemptCount,
            partialCleanupMismatchCount: partialCleanupMismatchCount,
            unexplainedManagedBytes: unexplainedManagedBytes
        )
    }

    private func unexplainedBytes(
        in root: URL,
        allowedPaths: Set<String>
    ) throws -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileAllocatedSizeKey,
            ]
        ) else {
            return 0
        }
        var bytes: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .fileAllocatedSizeKey]
            )
            guard values.isRegularFile == true,
                  !allowedPaths.contains(url.standardizedFileURL.path)
            else {
                continue
            }
            bytes += Int64(values.fileAllocatedSize ?? 0)
        }
        return bytes
    }
}
