import CryptoKit
import Foundation

struct ModelCatalogArtifactInspectionRequest: Equatable, Sendable {
    struct ExpectedFile: Equatable, Sendable {
        let relativePath: String
        let expectedSizeBytes: Int64
        let localPath: String?
    }

    let artifactID: String
    let expectedFiles: [ExpectedFile]
}

struct ModelCatalogArtifactVerificationRequest: Equatable, Sendable {
    struct ExpectedFile: Equatable, Sendable {
        let relativePath: String
        let expectedSizeBytes: Int64
        let expectedSHA256: String
        let localPath: String?
    }

    let artifactID: String
    let expectedFiles: [ExpectedFile]
}

enum ModelCatalogArtifactIntegrity: Equatable, Sendable {
    case notVerified
    case needsAttention
}

struct ModelCatalogArtifactLocalDetails: Equatable, Sendable {
    let artifactID: String
    let allocatedBytes: Int64
    let presentFileCount: Int
    let expectedFileCount: Int
    let missingRelativePaths: [String]
    let sizeMismatchRelativePaths: [String]
    let integrity: ModelCatalogArtifactIntegrity

    init(
        artifactID: String,
        allocatedBytes: Int64,
        presentFileCount: Int,
        expectedFileCount: Int,
        missingRelativePaths: [String],
        sizeMismatchRelativePaths: [String] = [],
        integrity: ModelCatalogArtifactIntegrity
    ) {
        self.artifactID = artifactID
        self.allocatedBytes = allocatedBytes
        self.presentFileCount = presentFileCount
        self.expectedFileCount = expectedFileCount
        self.missingRelativePaths = missingRelativePaths
        self.sizeMismatchRelativePaths = sizeMismatchRelativePaths
        self.integrity = integrity
    }
}

enum ModelCatalogArtifactInventoryReader {
    static func load(
        request: ModelCatalogArtifactInspectionRequest
    ) async throws -> ModelCatalogArtifactLocalDetails {
        let worker = Task.detached(priority: .utility) {
            var allocatedBytes: Int64 = 0
            var presentFileCount = 0
            var missingRelativePaths: [String] = []
            var sizeMismatchRelativePaths: [String] = []
            let resourceKeys: Set<URLResourceKey> = [
                .fileAllocatedSizeKey,
                .fileSizeKey,
                .isRegularFileKey,
                .totalFileAllocatedSizeKey,
            ]

            for expectedFile in request.expectedFiles {
                try Task.checkCancellation()
                guard let localPath = expectedFile.localPath else {
                    missingRelativePaths.append(expectedFile.relativePath)
                    continue
                }

                let values: URLResourceValues
                do {
                    values = try URL(fileURLWithPath: localPath)
                        .resourceValues(forKeys: resourceKeys)
                } catch {
                    missingRelativePaths.append(expectedFile.relativePath)
                    continue
                }
                guard values.isRegularFile == true else {
                    missingRelativePaths.append(expectedFile.relativePath)
                    continue
                }

                presentFileCount += 1
                allocatedBytes += Int64(
                    values.totalFileAllocatedSize
                        ?? values.fileAllocatedSize
                        ?? values.fileSize
                        ?? 0
                )
                if Int64(values.fileSize ?? -1) != expectedFile.expectedSizeBytes {
                    sizeMismatchRelativePaths.append(expectedFile.relativePath)
                }
            }

            let requiresAttention = !missingRelativePaths.isEmpty
                || !sizeMismatchRelativePaths.isEmpty
            return ModelCatalogArtifactLocalDetails(
                artifactID: request.artifactID,
                allocatedBytes: allocatedBytes,
                presentFileCount: presentFileCount,
                expectedFileCount: request.expectedFiles.count,
                missingRelativePaths: missingRelativePaths,
                sizeMismatchRelativePaths: sizeMismatchRelativePaths,
                integrity: requiresAttention ? .needsAttention : .notVerified
            )
        }

        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}

enum ModelCatalogArtifactVerifier {
    enum VerificationError: Error, Equatable {
        case missingFile
        case sizeMismatch
        case digestMismatch
    }

    static func verify(
        request: ModelCatalogArtifactVerificationRequest
    ) async throws {
        let worker = Task.detached(priority: .utility) {
            for expectedFile in request.expectedFiles {
                try Task.checkCancellation()
                guard let localPath = expectedFile.localPath else {
                    throw VerificationError.missingFile
                }
                let fileURL = URL(fileURLWithPath: localPath)
                guard let attributes = try? FileManager.default.attributesOfItem(
                    atPath: fileURL.path
                ),
                    let fileSize = attributes[.size] as? NSNumber
                else {
                    throw VerificationError.missingFile
                }
                guard fileSize.int64Value == expectedFile.expectedSizeBytes else {
                    throw VerificationError.sizeMismatch
                }
                guard try sha256Hex(fileURL: fileURL) == expectedFile.expectedSHA256 else {
                    throw VerificationError.digestMismatch
                }
            }
        }

        try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func sha256Hex(fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            guard !data.isEmpty else {
                break
            }
            hasher.update(data: data)
        }
        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
