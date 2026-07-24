import Darwin
import Foundation

public enum ModelStorageArtifactCondition: Equatable, Sendable {
    case complete
    case needsRepair
}

public struct ModelStorageArtifactInventory: Equatable, Sendable {
    public let artifactID: String
    public let installationReceiptPresent: Bool
    public let onDiskBytes: Int64?
    public let presentExpectedFileCount: Int
    public let expectedFileCount: Int
    public let missingExpectedRelativePaths: [String]
    public let sizeMismatchRelativePaths: [String]
    public let unexpectedFileCount: Int
    public let condition: ModelStorageArtifactCondition

    public init(
        artifactID: String,
        installationReceiptPresent: Bool,
        onDiskBytes: Int64?,
        presentExpectedFileCount: Int,
        expectedFileCount: Int,
        missingExpectedRelativePaths: [String],
        sizeMismatchRelativePaths: [String],
        unexpectedFileCount: Int,
        condition: ModelStorageArtifactCondition
    ) {
        self.artifactID = artifactID
        self.installationReceiptPresent = installationReceiptPresent
        self.onDiskBytes = onDiskBytes
        self.presentExpectedFileCount = presentExpectedFileCount
        self.expectedFileCount = expectedFileCount
        self.missingExpectedRelativePaths = missingExpectedRelativePaths
        self.sizeMismatchRelativePaths = sizeMismatchRelativePaths
        self.unexpectedFileCount = unexpectedFileCount
        self.condition = condition
    }
}

public struct ModelStorageInventorySummary: Equatable, Sendable {
    public let installedArtifactCount: Int
    public let installedModelStorageBytes: Int64
    public let downloadStorageBytes: Int64
    public let otherModelDataBytes: Int64
    public let totalManagedStorageBytes: Int64
    public let availableSpaceBytes: Int64?

    public init(
        installedArtifactCount: Int,
        installedModelStorageBytes: Int64,
        downloadStorageBytes: Int64,
        otherModelDataBytes: Int64,
        totalManagedStorageBytes: Int64,
        availableSpaceBytes: Int64?
    ) {
        self.installedArtifactCount = installedArtifactCount
        self.installedModelStorageBytes = installedModelStorageBytes
        self.downloadStorageBytes = downloadStorageBytes
        self.otherModelDataBytes = otherModelDataBytes
        self.totalManagedStorageBytes = totalManagedStorageBytes
        self.availableSpaceBytes = availableSpaceBytes
    }
}

public struct ModelStorageInventorySnapshot: Equatable, Sendable {
    public let artifacts: [ModelStorageArtifactInventory]
    public let summary: ModelStorageInventorySummary

    public init(
        artifacts: [ModelStorageArtifactInventory],
        summary: ModelStorageInventorySummary
    ) {
        self.artifacts = artifacts
        self.summary = summary
    }

    public func artifact(for artifactID: String) -> ModelStorageArtifactInventory? {
        artifacts.first { $0.artifactID == artifactID }
    }
}

public enum ModelStorageInventoryError: Error, Equatable {
    case filesystemReadFailed(String)
    case byteCountOverflow
}

public struct ModelStorageInventoryScanner: @unchecked Sendable {
    public typealias AvailableCapacity = @Sendable (URL) throws -> Int64

    private let layout: ModelStorageLayout
    private let fileManager: FileManager
    private let availableCapacity: AvailableCapacity

    public init(
        layout: ModelStorageLayout,
        fileManager: FileManager = .default,
        availableCapacity: @escaping AvailableCapacity = { url in
            try ModelVolumeCapacityProvider().availableCapacity(at: url)
        }
    ) {
        self.layout = layout
        self.fileManager = fileManager
        self.availableCapacity = availableCapacity
    }

    public func scan(
        installedRecords: [InstalledModelRecord]
    ) async throws -> ModelStorageInventorySnapshot {
        let worker = Task.detached(priority: .utility) {
            try scanSynchronously(installedRecords: installedRecords)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private func scanSynchronously(
        installedRecords: [InstalledModelRecord]
    ) throws -> ModelStorageInventorySnapshot {
        let installedRecords = InstalledModelsStore(
            records: installedRecords
        ).records
        let nodes = try nodesInManagedRoot()
        let nodesByPath = Dictionary(uniqueKeysWithValues: nodes.map {
            ($0.url.standardizedFileURL.path, $0)
        })
        let artifactRoots = installedRecords.compactMap {
            record -> ArtifactRoot? in
            guard let url = try? layout.installedModelDirectory(
                modelID: record.model.id
            ) else {
                return nil
            }
            return ArtifactRoot(
                artifactID: record.model.id,
                url: url.standardizedFileURL
            )
        }
        let validPartialPaths = validPartialPaths()
        let ownedNodes = nodes.map {
            OwnedNode(
                node: $0,
                owner: owner(
                    for: $0.url,
                    artifactRoots: artifactRoots,
                    validPartialPaths: validPartialPaths
                )
            )
        }
        let allocatedBytesByOwner = try allocatedBytesByOwner(ownedNodes)
        let inventoryByID = try installedRecords.reduce(
            into: [String: ModelStorageArtifactInventory]()
        ) { result, record in
            result[record.model.id] = try artifactInventory(
                record: record,
                artifactRoots: artifactRoots,
                nodesByPath: nodesByPath,
                ownedNodes: ownedNodes,
                allocatedBytesByOwner: allocatedBytesByOwner
            )
        }
        let artifacts = installedRecords.compactMap {
            inventoryByID[$0.model.id]
        }
        let installedBytes = try sum(
            artifacts.compactMap(\.onDiskBytes)
        )
        let downloadBytes = allocatedBytesByOwner[.download] ?? 0
        let otherBytes = allocatedBytesByOwner[.other] ?? 0
        let totalBytes = try sum([installedBytes, downloadBytes, otherBytes])
        let capacityURL = fileManager.fileExists(atPath: layout.rootDirectory.path)
            ? layout.rootDirectory
            : layout.rootDirectory.deletingLastPathComponent()
        let capacity = try? availableCapacity(capacityURL)

        return ModelStorageInventorySnapshot(
            artifacts: artifacts,
            summary: ModelStorageInventorySummary(
                installedArtifactCount: installedRecords.count,
                installedModelStorageBytes: installedBytes,
                downloadStorageBytes: downloadBytes,
                otherModelDataBytes: otherBytes,
                totalManagedStorageBytes: totalBytes,
                availableSpaceBytes: capacity
            )
        )
    }

    private func artifactInventory(
        record: InstalledModelRecord,
        artifactRoots: [ArtifactRoot],
        nodesByPath: [String: FileNode],
        ownedNodes: [OwnedNode],
        allocatedBytesByOwner: [StorageOwner: Int64]
    ) throws -> ModelStorageArtifactInventory {
        guard artifactRoots.contains(
            where: { $0.artifactID == record.model.id }
        ) else {
            return unavailableArtifactInventory(record: record)
        }

        var presentExpectedFileCount = 0
        var missingExpectedRelativePaths: [String] = []
        var sizeMismatchRelativePaths: [String] = []
        var expectedPaths: Set<String> = []

        for file in record.model.files {
            try Task.checkCancellation()
            let relativePath = file.relativePath ?? file.filename
            guard let expectedURL = expectedURL(
                record: record,
                filename: file.filename,
                relativePath: relativePath
            ) else {
                missingExpectedRelativePaths.append(relativePath)
                continue
            }
            let expectedPath = expectedURL.standardizedFileURL.path
            expectedPaths.insert(expectedPath)
            guard let node = nodesByPath[expectedPath],
                  node.kind == .regularFile
            else {
                missingExpectedRelativePaths.append(relativePath)
                continue
            }
            presentExpectedFileCount += 1
            if node.logicalSize != file.sizeBytes {
                sizeMismatchRelativePaths.append(relativePath)
            }
        }

        let unexpectedFileCount = ownedNodes.reduce(into: 0) { count, ownedNode in
            guard ownedNode.owner == .artifact(record.model.id),
                  ownedNode.node.kind != .directory,
                  !expectedPaths.contains(ownedNode.node.url.standardizedFileURL.path)
            else {
                return
            }
            count += 1
        }
        let condition: ModelStorageArtifactCondition =
            missingExpectedRelativePaths.isEmpty
                && sizeMismatchRelativePaths.isEmpty
                ? .complete
                : .needsRepair

        return ModelStorageArtifactInventory(
            artifactID: record.model.id,
            installationReceiptPresent: true,
            onDiskBytes: allocatedBytesByOwner[.artifact(record.model.id)] ?? 0,
            presentExpectedFileCount: presentExpectedFileCount,
            expectedFileCount: record.model.files.count,
            missingExpectedRelativePaths: missingExpectedRelativePaths,
            sizeMismatchRelativePaths: sizeMismatchRelativePaths,
            unexpectedFileCount: unexpectedFileCount,
            condition: condition
        )
    }

    private func unavailableArtifactInventory(
        record: InstalledModelRecord
    ) -> ModelStorageArtifactInventory {
        ModelStorageArtifactInventory(
            artifactID: record.model.id,
            installationReceiptPresent: true,
            onDiskBytes: nil,
            presentExpectedFileCount: 0,
            expectedFileCount: record.model.files.count,
            missingExpectedRelativePaths: record.model.files.map {
                $0.relativePath ?? $0.filename
            },
            sizeMismatchRelativePaths: [],
            unexpectedFileCount: 0,
            condition: .needsRepair
        )
    }

    private func expectedURL(
        record: InstalledModelRecord,
        filename: String,
        relativePath: String
    ) -> URL? {
        guard let receiptPath = record.localFilesByManifestFilename[filename],
              let managedURL = try? layout.installedArtifactURL(
                  modelID: record.model.id,
                  relativePath: relativePath
              ),
              URL(fileURLWithPath: receiptPath).standardizedFileURL.path
              == managedURL.standardizedFileURL.path
        else {
            return nil
        }
        return managedURL
    }

    private func nodesInManagedRoot() throws -> [FileNode] {
        guard let rootNode = try fileNode(at: layout.rootDirectory) else {
            return []
        }
        var result: [FileNode] = []
        var pending = [rootNode]
        while let node = pending.popLast() {
            try Task.checkCancellation()
            result.append(node)
            guard node.kind == .directory else {
                continue
            }
            let children: [URL]
            do {
                children = try fileManager.contentsOfDirectory(
                    at: node.url,
                    includingPropertiesForKeys: nil
                )
            } catch {
                throw ModelStorageInventoryError.filesystemReadFailed(node.url.path)
            }
            for child in children.sorted(by: { $0.path > $1.path }) {
                if let childNode = try fileNode(at: child) {
                    pending.append(childNode)
                }
            }
        }
        return result
    }

    private func fileNode(at url: URL) throws -> FileNode? {
        var information = stat()
        guard Darwin.lstat(url.path, &information) == 0 else {
            if errno == ENOENT {
                return nil
            }
            throw ModelStorageInventoryError.filesystemReadFailed(url.path)
        }
        let mode = information.st_mode & mode_t(S_IFMT)
        let kind: FileNode.Kind = switch mode {
        case mode_t(S_IFDIR):
            .directory
        case mode_t(S_IFREG):
            .regularFile
        case mode_t(S_IFLNK):
            .symbolicLink
        default:
            .other
        }
        let blocks = max(Int64(information.st_blocks), 0)
        let allocated = blocks.multipliedReportingOverflow(by: 512)
        guard !allocated.overflow else {
            throw ModelStorageInventoryError.byteCountOverflow
        }
        return FileNode(
            url: url.standardizedFileURL,
            identity: FileIdentity(
                device: UInt64(information.st_dev),
                inode: UInt64(information.st_ino)
            ),
            allocatedBytes: allocated.partialValue,
            logicalSize: Int64(information.st_size),
            kind: kind
        )
    }

    private func validPartialPaths() -> Set<String> {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: layout.downloadsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return Set(
            urls
                .filter { $0.lastPathComponent.hasSuffix(".resume.json") }
                .compactMap {
                    ModelDownloadStorageValidation.validatedPartialURL(
                        for: $0,
                        fileManager: fileManager
                    )
                }
                .map(\.standardizedFileURL.path)
        )
    }

    private func owner(
        for url: URL,
        artifactRoots: [ArtifactRoot],
        validPartialPaths: Set<String>
    ) -> StorageOwner {
        let path = url.standardizedFileURL.path
        if let root = artifactRoots.first(where: {
            path == $0.url.path || path.hasPrefix($0.url.path + "/")
        }) {
            return .artifact(root.artifactID)
        }
        if validPartialPaths.contains(path) {
            return .download
        }
        return .other
    }

    private func allocatedBytesByOwner(
        _ nodes: [OwnedNode]
    ) throws -> [StorageOwner: Int64] {
        var seenIdentities: Set<FileIdentity> = []
        var result: [StorageOwner: Int64] = [:]
        for ownedNode in nodes.sorted(by: ownerPriority) {
            try Task.checkCancellation()
            guard seenIdentities.insert(ownedNode.node.identity).inserted else {
                continue
            }
            result[ownedNode.owner] = try sum([
                result[ownedNode.owner] ?? 0,
                ownedNode.node.allocatedBytes,
            ])
        }
        return result
    }

    private func ownerPriority(_ lhs: OwnedNode, _ rhs: OwnedNode) -> Bool {
        if lhs.owner.categoryRank != rhs.owner.categoryRank {
            return lhs.owner.categoryRank < rhs.owner.categoryRank
        }
        if lhs.owner.artifactID != rhs.owner.artifactID {
            return (lhs.owner.artifactID ?? "") < (rhs.owner.artifactID ?? "")
        }
        return lhs.node.url.path < rhs.node.url.path
    }

    private func sum(_ values: [Int64]) throws -> Int64 {
        try values.reduce(0) { current, value in
            let addition = current.addingReportingOverflow(value)
            guard !addition.overflow else {
                throw ModelStorageInventoryError.byteCountOverflow
            }
            return addition.partialValue
        }
    }
}

private struct ArtifactRoot {
    let artifactID: String
    let url: URL
}

private struct FileIdentity: Hashable {
    let device: UInt64
    let inode: UInt64
}

private struct FileNode {
    enum Kind: Equatable {
        case directory
        case regularFile
        case symbolicLink
        case other
    }

    let url: URL
    let identity: FileIdentity
    let allocatedBytes: Int64
    let logicalSize: Int64
    let kind: Kind
}

private enum StorageOwner: Hashable {
    case artifact(String)
    case download
    case other

    var categoryRank: Int {
        switch self {
        case .artifact:
            0
        case .download:
            1
        case .other:
            2
        }
    }

    var artifactID: String? {
        switch self {
        case let .artifact(artifactID):
            artifactID
        case .download, .other:
            nil
        }
    }
}

private struct OwnedNode {
    let node: FileNode
    let owner: StorageOwner
}
