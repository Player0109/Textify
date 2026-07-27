import Foundation
import XCTest

@testable import TextifyModels

final class ModelSelectionCopyPolicyTests: XCTestCase {
    func testProductionManifestPassesMultiVersionSelectionCopyPolicy() throws {
        XCTAssertNoThrow(
            try ProductionModelPolicy.validateProductionManifest(
                productionManifest()
            )
        )
    }

    func testDuplicateSiblingTradeoffIsRejected() throws {
        var root = try productionJSON()
        let source = try tradeoff(
            modelID: "whisper-large-v3-turbo-q5_0",
            in: root
        )
        try setTradeoff(
            source,
            modelID: "whisper-large-v3-turbo-mlx",
            in: &root
        )

        XCTAssertThrowsError(
            try ProductionModelPolicy.validateProductionManifest(
                decode(root)
            )
        ) {
            XCTAssertEqual(
                $0 as? ProductionModelPolicyError,
                .invalidVariantSelectionCopy(
                    checkpointID:
                        "checkpoint.openai.whisper-large-v3-turbo",
                    reason: .duplicateAccuracyTradeoff
                )
            )
        }
    }

    func testTradeoffOverTwoHundredCharactersIsRejected() throws {
        var root = try productionJSON()
        try setTradeoff(
            String(repeating: "x", count: 201),
            modelID: "whisper-large-v3-turbo-mlx",
            in: &root
        )

        XCTAssertThrowsError(
            try ProductionModelPolicy.validateProductionManifest(
                decode(root)
            )
        ) {
            XCTAssertEqual(
                $0 as? ProductionModelPolicyError,
                .invalidVariantSelectionCopy(
                    checkpointID:
                        "checkpoint.openai.whisper-large-v3-turbo",
                    reason: .accuracyTradeoffTooLong
                )
            )
        }
    }

    func testUnsupportedAccuracySuperlativeIsRejected() throws {
        var root = try productionJSON()
        try setTradeoff(
            "Best measured accuracy.",
            modelID: "parakeet-tdt-0.6b-v3-q5-k-m",
            in: &root
        )

        XCTAssertThrowsError(
            try ProductionModelPolicy.validateProductionManifest(
                decode(root)
            )
        ) {
            XCTAssertEqual(
                $0 as? ProductionModelPolicyError,
                .invalidVariantSelectionCopy(
                    checkpointID:
                        "checkpoint.nvidia.parakeet-tdt-0.6b-v3",
                    reason: .unsupportedAccuracySuperlative
                )
            )
        }
    }

    func testDivergentSiblingLanguagesMustBeDisclosed() throws {
        var root = try productionJSON()
        try setTradeoff(
            "Larger full-precision build with a different language set.",
            modelID: "whisper-large-v3-turbo-mlx",
            in: &root
        )

        XCTAssertThrowsError(
            try ProductionModelPolicy.validateProductionManifest(
                decode(root)
            )
        ) {
            XCTAssertEqual(
                $0 as? ProductionModelPolicyError,
                .invalidVariantSelectionCopy(
                    checkpointID:
                        "checkpoint.openai.whisper-large-v3-turbo",
                    reason: .languageDifferenceNotDisclosed
                )
            )
        }
    }

    private func productionManifest() throws -> ModelManifest {
        try ModelManifest.decode(
            Data(
                contentsOf:
                    repositoryRoot
                    .appendingPathComponent("models/manifest.json")
            )
        )
    }

    private func productionJSON() throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(
                    contentsOf:
                        repositoryRoot
                        .appendingPathComponent("models/manifest.json")
                )
            ) as? [String: Any]
        )
    }

    private func decode(_ root: [String: Any]) throws -> ModelManifest {
        try ModelManifest.decode(
            JSONSerialization.data(withJSONObject: root)
        )
    }

    private func tradeoff(
        modelID: String,
        in root: [String: Any]
    ) throws -> String {
        let models = try XCTUnwrap(root["models"] as? [[String: Any]])
        let model = try XCTUnwrap(
            models.first { $0["id"] as? String == modelID }
        )
        let presentation = try XCTUnwrap(
            model["presentation"] as? [String: Any]
        )
        return try XCTUnwrap(presentation["accuracyTradeoff"] as? String)
    }

    private func setTradeoff(
        _ value: String,
        modelID: String,
        in root: inout [String: Any]
    ) throws {
        var models = try XCTUnwrap(root["models"] as? [[String: Any]])
        let index = try XCTUnwrap(
            models.firstIndex { $0["id"] as? String == modelID }
        )
        var model = models[index]
        var presentation = try XCTUnwrap(
            model["presentation"] as? [String: Any]
        )
        presentation["accuracyTradeoff"] = value
        model["presentation"] = presentation
        models[index] = model
        root["models"] = models
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
