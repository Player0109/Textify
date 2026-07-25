import Foundation
@testable import TextifyModels
import XCTest

final class ModelStorageAdmissionTests: XCTestCase {
    func testInstallationExpansionRejectsCountSizeAndDepthLimits() {
        let policy = ModelInstallationExpansionPolicy(
            maximumEntryCount: 2,
            maximumExpandedBytes: 10,
            maximumPathDepth: 2
        )

        XCTAssertThrowsError(try policy.validate([
            .init(relativePath: "a", expandedBytes: 1),
            .init(relativePath: "b", expandedBytes: 1),
            .init(relativePath: "c", expandedBytes: 1),
        ]))
        XCTAssertThrowsError(try policy.validate([
            .init(relativePath: "model.bin", expandedBytes: 11),
        ]))
        XCTAssertThrowsError(try policy.validate([
            .init(relativePath: "a/b/c", expandedBytes: 1),
        ]))
    }

    func testInstallationExpansionAcceptsDeclaredLimits() throws {
        try ModelInstallationExpansionPolicy(
            maximumEntryCount: 2,
            maximumExpandedBytes: 10,
            maximumPathDepth: 2
        ).validate([
            .init(relativePath: "a/one", expandedBytes: 4),
            .init(relativePath: "b/two", expandedBytes: 6),
        ])
    }

    func testFreshDirectFileRequiresPeakBytesAndCompleteArtifactMargin() {
        let requirement = ModelStorageAdmissionRequirement(
            completeTransferBytes: 100,
            finalArtifactBytes: 100,
            peakInstallationBytes: 100
        )

        XCTAssertEqual(
            requirement.requiredAdditionalCapacity(
                reusable: ModelReusableStorage(
                    validatedLogicalBytes: 0,
                    allocatedBytes: 0
                )
            ),
            500_000_100
        )
    }

    func testResumeCreditIsLesserOfValidatedLogicalAndAllocatedBytes() {
        let requirement = ModelStorageAdmissionRequirement(
            completeTransferBytes: 100,
            finalArtifactBytes: 100,
            peakInstallationBytes: 100
        )

        XCTAssertEqual(
            requirement.requiredAdditionalCapacity(
                reusable: ModelReusableStorage(
                    validatedLogicalBytes: 60,
                    allocatedBytes: 40
                )
            ),
            500_000_060
        )
    }

    func testReusableCreditIsCappedPerFileBeforeAggregation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TextifyModelStorageAdmissionTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let denseURL = directory.appendingPathComponent("dense.bin")
        let sparseURL = directory.appendingPathComponent("sparse.bin")
        let denseLogicalBytes: Int64 = 1
        let sparseLogicalBytes: Int64 = 1_048_576
        try Data([1]).write(to: denseURL)
        FileManager.default.createFile(
            atPath: sparseURL.path,
            contents: nil
        )
        let sparseHandle = try FileHandle(forWritingTo: sparseURL)
        try sparseHandle.truncate(atOffset: UInt64(sparseLogicalBytes))
        try sparseHandle.close()
        let denseAllocation = try XCTUnwrap(
            ModelStorageAllocation.regularFile(at: denseURL)
        )
        let sparseAllocation = try XCTUnwrap(
            ModelStorageAllocation.regularFile(at: sparseURL)
        )
        XCTAssertGreaterThan(
            denseAllocation.allocatedBytes,
            denseLogicalBytes
        )
        XCTAssertLessThan(
            sparseAllocation.allocatedBytes,
            sparseLogicalBytes
        )

        let reusable = try ModelReusableStorageInspector.inspect(
            layout: ModelStorageLayout(rootDirectory: directory),
            modelID: "artifact-a",
            additionalValidatedFiles: [
                (denseURL, denseLogicalBytes),
                (sparseURL, sparseLogicalBytes),
            ]
        ).storage
        let expectedCredit = min(
            denseLogicalBytes,
            denseAllocation.allocatedBytes
        ) + min(
            sparseLogicalBytes,
            sparseAllocation.allocatedBytes
        )

        XCTAssertEqual(
            reusable.validatedLogicalBytes,
            denseLogicalBytes + sparseLogicalBytes
        )
        XCTAssertEqual(
            reusable.allocatedBytes,
            denseAllocation.allocatedBytes
                + sparseAllocation.allocatedBytes
        )
        XCTAssertEqual(reusable.creditBytes, expectedCredit)
        XCTAssertLessThan(
            reusable.creditBytes,
            min(
                reusable.validatedLogicalBytes,
                reusable.allocatedBytes
            )
        )
    }

    func testDirectoryStagingUsesSignedPeakBound() {
        let requirement = ModelStorageAdmissionRequirement(
            completeTransferBytes: 300,
            finalArtifactBytes: 300,
            peakInstallationBytes: 300
        )
        XCTAssertEqual(
            requirement.requiredAdditionalCapacity(
                reusable: ModelReusableStorage(
                    validatedLogicalBytes: 100,
                    allocatedBytes: 100
                )
            ),
            500_000_200
        )
    }

    func testArchiveExpansionRechecksSignedPeakImmediatelyBeforeGrowth() throws {
        let requirement = ModelStorageAdmissionRequirement(
            completeTransferBytes: 100,
            finalArtifactBytes: 300,
            peakInstallationBytes: 400
        )
        try requirement.requireCapacity(
            availableBytes: 500_000_400,
            reusable: .none
        )
        var didExpand = false

        XCTAssertThrowsError(
            try performStorageGrowth(
                requirement: requirement,
                availableBytes: 500_000_299,
                reusable: ModelReusableStorage(
                    validatedLogicalBytes: 100,
                    allocatedBytes: 100
                )
            ) {
                didExpand = true
            }
        ) { error in
            XCTAssertEqual(
                error as? ModelInstallError,
                .insufficientDiskSpace(
                    requiredBytes: 500_000_300,
                    availableBytes: 500_000_299
                )
            )
        }
        XCTAssertFalse(didExpand)
    }

    func testConversionRechecksSignedPeakImmediatelyBeforeGrowth() throws {
        let requirement = ModelStorageAdmissionRequirement(
            completeTransferBytes: 100,
            finalArtifactBytes: 200,
            peakInstallationBytes: 300
        )
        var didConvert = false

        try performStorageGrowth(
            requirement: requirement,
            availableBytes: 500_000_200,
            reusable: ModelReusableStorage(
                validatedLogicalBytes: 100,
                allocatedBytes: 100
            )
        ) {
            didConvert = true
        }

        XCTAssertTrue(didConvert)
    }

    func testSafetyMarginUsesTwentyPercentForLargeCompleteArtifact() {
        let requirement = ModelStorageAdmissionRequirement(
            completeTransferBytes: 4_000_000_000,
            finalArtifactBytes: 3_000_000_000,
            peakInstallationBytes: 4_000_000_000
        )

        XCTAssertEqual(requirement.safetyMarginBytes, 800_000_000)
        XCTAssertEqual(
            requirement.requiredAdditionalCapacity(reusable: .none),
            4_800_000_000
        )
    }

    func testSafetyMarginRoundsTwentyPercentUpToACompleteByte() {
        let requirement = ModelStorageAdmissionRequirement(
            completeTransferBytes: 3_000_000_001,
            finalArtifactBytes: 3_000_000_000,
            peakInstallationBytes: 3_000_000_001
        )

        XCTAssertEqual(requirement.safetyMarginBytes, 600_000_001)
    }

    func testArithmeticOverflowFailsClosed() {
        let requirement = ModelStorageAdmissionRequirement(
            completeTransferBytes: .max,
            finalArtifactBytes: .max,
            peakInstallationBytes: .max
        )

        XCTAssertEqual(
            requirement.requiredAdditionalCapacity(reusable: .none),
            .max
        )
    }

    func testVolumeCapacityPrefersImportantUsageThenFallsBackToOrdinary() throws {
        let url = URL(fileURLWithPath: "/volume")
        let important = ModelVolumeCapacityProvider { requestedURL in
            XCTAssertEqual(requestedURL, url)
            return ModelVolumeCapacityValues(
                importantUsageBytes: 900,
                ordinaryBytes: 1_000
            )
        }
        let fallback = ModelVolumeCapacityProvider { _ in
            ModelVolumeCapacityValues(
                importantUsageBytes: nil,
                ordinaryBytes: 700
            )
        }

        XCTAssertEqual(try important.availableCapacity(at: url), 900)
        XCTAssertEqual(try fallback.availableCapacity(at: url), 700)
    }

    func testVolumeCapacityFailsClosedWhenNeitherMeasurementExists() {
        let provider = ModelVolumeCapacityProvider { _ in
            ModelVolumeCapacityValues(
                importantUsageBytes: nil,
                ordinaryBytes: nil
            )
        }

        XCTAssertThrowsError(
            try provider.availableCapacity(
                at: URL(fileURLWithPath: "/volume")
            )
        ) { error in
            XCTAssertEqual(
                error as? ModelStorageAdmissionError,
                .capacityUnavailable
            )
        }
    }

    private func performStorageGrowth(
        requirement: ModelStorageAdmissionRequirement,
        availableBytes: Int64,
        reusable: ModelReusableStorage,
        operation: () -> Void
    ) throws {
        try requirement.requireCapacity(
            availableBytes: availableBytes,
            reusable: reusable
        )
        operation()
    }
}
