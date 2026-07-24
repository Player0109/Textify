import CryptoKit
import Foundation
import TextifyModels

struct ModelCatalogArtifactVerificationRequest: Equatable {
    struct ExpectedFile: Equatable {
        let relativePath: String
        let expectedSizeBytes: Int64
        let expectedSHA256: String
        let localPath: String?
    }

    let artifactID: String
    let expectedFiles: [ExpectedFile]
}

enum ModelCatalogArtifactIntegrity: Equatable {
    case notVerified
    case needsAttention
}

struct ModelCatalogArtifactLocalDetails: Equatable {
    let artifactID: String
    let allocatedBytes: Int64?
    let presentFileCount: Int
    let expectedFileCount: Int
    let missingRelativePaths: [String]
    let sizeMismatchRelativePaths: [String]
    let unexpectedFileCount: Int
    let integrity: ModelCatalogArtifactIntegrity

    init(
        artifactID: String,
        allocatedBytes: Int64?,
        presentFileCount: Int,
        expectedFileCount: Int,
        missingRelativePaths: [String],
        sizeMismatchRelativePaths: [String] = [],
        unexpectedFileCount: Int = 0,
        integrity: ModelCatalogArtifactIntegrity
    ) {
        self.artifactID = artifactID
        self.allocatedBytes = allocatedBytes
        self.presentFileCount = presentFileCount
        self.expectedFileCount = expectedFileCount
        self.missingRelativePaths = missingRelativePaths
        self.sizeMismatchRelativePaths = sizeMismatchRelativePaths
        self.unexpectedFileCount = unexpectedFileCount
        self.integrity = integrity
    }

    init(inventory: ModelStorageArtifactInventory) {
        self.init(
            artifactID: inventory.artifactID,
            allocatedBytes: inventory.onDiskBytes,
            presentFileCount: inventory.presentExpectedFileCount,
            expectedFileCount: inventory.expectedFileCount,
            missingRelativePaths: inventory.missingExpectedRelativePaths,
            sizeMismatchRelativePaths: inventory.sizeMismatchRelativePaths,
            unexpectedFileCount: inventory.unexpectedFileCount,
            integrity: inventory.condition == .needsRepair
                ? .needsAttention
                : .notVerified
        )
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
