import Darwin
import Foundation

public enum ModelStorageAdmissionError: Error, Equatable {
    case capacityUnavailable
}

public struct ModelReusableStorage: Equatable, Sendable {
    public static let none = ModelReusableStorage(
        validatedLogicalBytes: 0,
        allocatedBytes: 0
    )

    public let validatedLogicalBytes: Int64
    public let allocatedBytes: Int64
    public let creditBytes: Int64

    public init(
        validatedLogicalBytes: Int64,
        allocatedBytes: Int64
    ) {
        self.validatedLogicalBytes = max(0, validatedLogicalBytes)
        self.allocatedBytes = max(0, allocatedBytes)
        self.creditBytes = min(
            self.validatedLogicalBytes,
            self.allocatedBytes
        )
    }

    fileprivate init(
        validatedLogicalBytes: Int64,
        allocatedBytes: Int64,
        attributedCreditBytes: Int64
    ) {
        self.validatedLogicalBytes = max(0, validatedLogicalBytes)
        self.allocatedBytes = max(0, allocatedBytes)
        self.creditBytes = min(
            max(0, attributedCreditBytes),
            min(
                self.validatedLogicalBytes,
                self.allocatedBytes
            )
        )
    }
}

public struct ModelStorageAdmissionRequirement: Equatable, Sendable {
    public static let minimumSafetyMarginBytes: Int64 = 500_000_000

    public let completeTransferBytes: Int64
    public let finalArtifactBytes: Int64
    public let peakInstallationBytes: Int64

    public init(
        completeTransferBytes: Int64,
        finalArtifactBytes: Int64,
        peakInstallationBytes: Int64
    ) {
        self.completeTransferBytes = max(0, completeTransferBytes)
        self.finalArtifactBytes = max(0, finalArtifactBytes)
        self.peakInstallationBytes = max(0, peakInstallationBytes)
    }

    public var safetyMarginBytes: Int64 {
        let completeArtifactBytes = max(
            completeTransferBytes,
            finalArtifactBytes
        )
        let twentyPercent = completeArtifactBytes / 5
            + (completeArtifactBytes % 5 == 0 ? 0 : 1)
        return max(
            Self.minimumSafetyMarginBytes,
            twentyPercent
        )
    }

    public func requiredAdditionalCapacity(
        reusable: ModelReusableStorage
    ) -> Int64 {
        let remainingPeak = peakInstallationBytes
            - min(peakInstallationBytes, reusable.creditBytes)
        let total = remainingPeak.addingReportingOverflow(
            safetyMarginBytes
        )
        return total.overflow ? .max : total.partialValue
    }

    public func requireCapacity(
        availableBytes: Int64,
        reusable: ModelReusableStorage
    ) throws {
        let requiredBytes = requiredAdditionalCapacity(reusable: reusable)
        guard availableBytes >= requiredBytes else {
            throw ModelInstallError.insufficientDiskSpace(
                requiredBytes: requiredBytes,
                availableBytes: availableBytes
            )
        }
    }
}

public struct ModelVolumeCapacityValues: Equatable, Sendable {
    public let importantUsageBytes: Int64?
    public let ordinaryBytes: Int64?

    public init(
        importantUsageBytes: Int64?,
        ordinaryBytes: Int64?
    ) {
        self.importantUsageBytes = importantUsageBytes
        self.ordinaryBytes = ordinaryBytes
    }
}

public struct ModelVolumeCapacityProvider: Sendable {
    public typealias ReadValues = @Sendable (
        URL
    ) throws -> ModelVolumeCapacityValues

    private let readValues: ReadValues

    public init(
        _ readValues: @escaping ReadValues = { url in
            let values = try url.resourceValues(
                forKeys: [
                    .volumeAvailableCapacityForImportantUsageKey,
                    .volumeAvailableCapacityKey,
                ]
            )
            return ModelVolumeCapacityValues(
                importantUsageBytes:
                    values.volumeAvailableCapacityForImportantUsage,
                ordinaryBytes: values.volumeAvailableCapacity.map(Int64.init)
            )
        }
    ) {
        self.readValues = readValues
    }

    public func availableCapacity(at url: URL) throws -> Int64 {
        let values = try readValues(url)
        if let important = values.importantUsageBytes, important >= 0 {
            return important
        }
        if let ordinary = values.ordinaryBytes, ordinary >= 0 {
            return ordinary
        }
        throw ModelStorageAdmissionError.capacityUnavailable
    }
}

struct ModelRegularFileAllocation: Equatable {
    let identity: ModelStorageFileIdentity
    let allocatedBytes: Int64
}

struct ModelStorageFileIdentity: Hashable {
    let device: UInt64
    let inode: UInt64
}

enum ModelStorageAllocation {
    static func regularFile(at url: URL) -> ModelRegularFileAllocation? {
        var information = stat()
        guard Darwin.lstat(url.path, &information) == 0,
              information.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
        else {
            return nil
        }
        let allocated = max(Int64(information.st_blocks), 0)
            .multipliedReportingOverflow(by: 512)
        guard !allocated.overflow else {
            return nil
        }
        return ModelRegularFileAllocation(
            identity: ModelStorageFileIdentity(
                device: UInt64(information.st_dev),
                inode: UInt64(information.st_ino)
            ),
            allocatedBytes: allocated.partialValue
        )
    }
}

struct ModelValidatedReusableStorage {
    let storage: ModelReusableStorage
    let fileCount: Int
}

enum ModelReusableStorageInspector {
    static func inspect(
        layout: ModelStorageLayout,
        modelID: String,
        expectedFiles: [ModelFile]? = nil,
        additionalValidatedFiles: [(url: URL, logicalBytes: Int64)] = [],
        fileManager: FileManager = .default
    ) throws -> ModelValidatedReusableStorage {
        var accumulator = ReusableStorageAccumulator()
        if fileManager.fileExists(atPath: layout.downloadsDirectory.path) {
            let metadataURLs = try fileManager.contentsOfDirectory(
                at: layout.downloadsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).filter {
                $0.lastPathComponent.hasSuffix(".resume.json")
            }
            for metadataURL in metadataURLs {
                guard let partialURL = ModelDownloadStorageValidation
                    .validatedPartialURL(
                        for: metadataURL,
                        expectedModelID: modelID,
                        expectedFiles: expectedFiles,
                        fileManager: fileManager
                    ),
                let logicalBytes = try? partialURL.resourceValues(
                    forKeys: [.fileSizeKey]
                ).fileSize
                else {
                    continue
                }
                accumulator.add(
                    url: partialURL,
                    logicalBytes: Int64(logicalBytes)
                )
            }
        }
        for file in additionalValidatedFiles {
            accumulator.add(
                url: file.url,
                logicalBytes: file.logicalBytes
            )
        }
        return accumulator.result
    }
}

private struct ReusableStorageAccumulator {
    private var validatedLogicalBytes: Int64 = 0
    private var allocatedBytes: Int64 = 0
    private var attributedCreditBytes: Int64 = 0
    private var identities: Set<ModelStorageFileIdentity> = []
    private var fileCount = 0
    private var isInvalid = false

    mutating func add(url: URL, logicalBytes: Int64) {
        guard !isInvalid,
              logicalBytes > 0,
              let allocation = ModelStorageAllocation.regularFile(at: url),
              identities.insert(allocation.identity).inserted
        else {
            return
        }
        let logical = validatedLogicalBytes.addingReportingOverflow(
            logicalBytes
        )
        let allocated = allocatedBytes.addingReportingOverflow(
            allocation.allocatedBytes
        )
        let attributedCredit = attributedCreditBytes.addingReportingOverflow(
            min(logicalBytes, allocation.allocatedBytes)
        )
        guard !logical.overflow,
              !allocated.overflow,
              !attributedCredit.overflow
        else {
            isInvalid = true
            validatedLogicalBytes = 0
            allocatedBytes = 0
            attributedCreditBytes = 0
            identities.removeAll()
            fileCount = 0
            return
        }
        validatedLogicalBytes = logical.partialValue
        allocatedBytes = allocated.partialValue
        attributedCreditBytes = attributedCredit.partialValue
        fileCount += 1
    }

    var result: ModelValidatedReusableStorage {
        ModelValidatedReusableStorage(
            storage: isInvalid
                ? .none
                : ModelReusableStorage(
                    validatedLogicalBytes: validatedLogicalBytes,
                    allocatedBytes: allocatedBytes,
                    attributedCreditBytes: attributedCreditBytes
                ),
            fileCount: isInvalid ? 0 : fileCount
        )
    }
}
