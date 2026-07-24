import Foundation
import TextifyModels
import XCTest

final class ManifestV3Tests: XCTestCase {
    func testSignedV3FixtureVerifiesAndPassesProductionPolicy() throws {
        let manifestData = try fixtureData("manifest_v3.json")
        let verifier = ManifestVerifier(trustedKeys: [
            TrustedModelManifestKey(
                keyId: "fixture-v3-key",
                publicKeyBase64: try fixtureString("manifest_v3.fixture-public-key.base64")
            )
        ])

        let manifest = try verifier.verify(
            manifestData: manifestData,
            signatureData: try fixtureData("manifest_v3.json.sig")
        )

        XCTAssertEqual(manifest.manifestVersion, 3)
        XCTAssertNoThrow(try ProductionModelPolicy.validateProductionManifest(manifest))

        let graph = try XCTUnwrap(manifest.presentationGraph)
        XCTAssertEqual(graph.families.map(\.id), ["family.whisper"])
        XCTAssertEqual(
            graph.checkpoints.map(\.id),
            ["checkpoint.whisper.small", "checkpoint.whisper.tiny"]
        )
        XCTAssertEqual(
            graph.checkpoints.map(\.artifactIDs.count),
            [2, 1],
            "The fixture must exercise multi-variant and single-variant checkpoints"
        )

        let artifact = try XCTUnwrap(
            graph.artifacts.first { $0.id == "whisper-small-q5_1" }
        )
        XCTAssertEqual(artifact.artifactFormat, .ggml)
        XCTAssertEqual(artifact.numericFormat, .q5_1)
        XCTAssertEqual(artifact.runtime, .whisperCpp)
        XCTAssertEqual(artifact.computeRoute, .gpuViaMetal)
        XCTAssertEqual(artifact.compatibility.supportedArchitectures, [.arm64])
        XCTAssertEqual(artifact.presentation.displayName, "Q5_1")
    }

    func testV3GraphRejectsDuplicateIDs() throws {
        var json = try fixtureJSON()
        var graph = try presentationGraph(in: json)
        var families = try XCTUnwrap(graph["families"] as? [[String: Any]])
        families.append(families[0])
        graph["families"] = families
        json["presentationGraph"] = graph

        assertGraphPolicyError(
            json,
            equals: .duplicateID("family.whisper")
        )
    }

    func testV3GraphRejectsMissingReferences() throws {
        var json = try fixtureJSON()
        var graph = try presentationGraph(in: json)
        var families = try XCTUnwrap(graph["families"] as? [[String: Any]])
        families[0]["checkpointIDs"] = ["checkpoint.missing"]
        graph["families"] = families
        json["presentationGraph"] = graph

        assertGraphPolicyError(
            json,
            equals: .missingReference(
                ownerID: "family.whisper",
                referenceID: "checkpoint.missing"
            )
        )
    }

    func testV3GraphRejectsMultipleOwnership() throws {
        var json = try fixtureJSON()
        var graph = try presentationGraph(in: json)
        var families = try XCTUnwrap(graph["families"] as? [[String: Any]])
        var secondFamily = families[0]
        secondFamily["id"] = "family.whisper-alias"
        secondFamily["checkpointIDs"] = ["checkpoint.whisper.small"]
        var presentation = try XCTUnwrap(secondFamily["presentation"] as? [String: Any])
        presentation["curatedRank"] = 20
        secondFamily["presentation"] = presentation
        families.append(secondFamily)
        graph["families"] = families
        json["presentationGraph"] = graph

        assertGraphPolicyError(
            json,
            equals: .multipleOwnership(recordID: "checkpoint.whisper.small")
        )
    }

    func testV3GraphRejectsExactArtifactOwnedByMultipleCheckpoints() throws {
        var json = try fixtureJSON()
        var graph = try presentationGraph(in: json)
        var artifacts = try XCTUnwrap(graph["artifacts"] as? [[String: Any]])
        var tinyPresentation = try XCTUnwrap(artifacts[2]["presentation"] as? [String: Any])
        tinyPresentation["curatedRank"] = 30
        artifacts[2]["presentation"] = tinyPresentation
        graph["artifacts"] = artifacts
        var checkpoints = try XCTUnwrap(graph["checkpoints"] as? [[String: Any]])
        checkpoints[1]["artifactIDs"] = [
            "whisper-tiny-f16",
            "whisper-small-q5_1",
        ]
        graph["checkpoints"] = checkpoints
        json["presentationGraph"] = graph

        assertGraphPolicyError(
            json,
            equals: .multipleOwnership(recordID: "whisper-small-q5_1")
        )
    }

    func testV3GraphRejectsPurposeMismatch() throws {
        var json = try fixtureJSON()
        var graph = try presentationGraph(in: json)
        var checkpoints = try XCTUnwrap(graph["checkpoints"] as? [[String: Any]])
        checkpoints[0]["purpose"] = "voice_cleaning"
        graph["checkpoints"] = checkpoints
        json["presentationGraph"] = graph

        assertGraphPolicyError(
            json,
            equals: .purposeMismatch(recordID: "checkpoint.whisper.small")
        )
    }

    func testV3GraphRejectsExactArtifactPurposeMismatch() throws {
        var json = try fixtureJSON()
        var graph = try presentationGraph(in: json)
        var artifacts = try XCTUnwrap(graph["artifacts"] as? [[String: Any]])
        artifacts[0]["purpose"] = "voice_cleaning"
        graph["artifacts"] = artifacts
        json["presentationGraph"] = graph

        assertGraphPolicyError(
            json,
            equals: .purposeMismatch(recordID: "whisper-small-q5_1")
        )
    }

    func testV3GraphRejectsUnreachableRecords() throws {
        var json = try fixtureJSON()
        var graph = try presentationGraph(in: json)
        var families = try XCTUnwrap(graph["families"] as? [[String: Any]])
        families[0]["checkpointIDs"] = ["checkpoint.whisper.small"]
        graph["families"] = families
        json["presentationGraph"] = graph

        assertGraphPolicyError(
            json,
            equals: .unreachableRecord("checkpoint.whisper.tiny")
        )
    }

    func testV3GraphRejectsOperationalArtifactMissingFromPresentationGraph() throws {
        var json = try fixtureJSON()
        var graph = try presentationGraph(in: json)
        var checkpoints = try XCTUnwrap(graph["checkpoints"] as? [[String: Any]])
        checkpoints[0]["artifactIDs"] = ["whisper-small-q5_1"]
        checkpoints[0]["fallbackArtifactIDs"] = []
        graph["checkpoints"] = checkpoints
        var artifacts = try XCTUnwrap(graph["artifacts"] as? [[String: Any]])
        artifacts.removeAll { ($0["id"] as? String) == "whisper-small-q8_0" }
        graph["artifacts"] = artifacts
        json["presentationGraph"] = graph

        assertGraphPolicyError(
            json,
            equals: .unreachableRecord("whisper-small-q8_0")
        )
    }

    func testV3StrictDecodeRejectsUnknownNestedStructure() throws {
        var json = try fixtureJSON()
        var graph = try presentationGraph(in: json)
        var artifacts = try XCTUnwrap(graph["artifacts"] as? [[String: Any]])
        var presentation = try XCTUnwrap(artifacts[0]["presentation"] as? [String: Any])
        presentation["unsignedGuess"] = "FP16"
        artifacts[0]["presentation"] = presentation
        graph["artifacts"] = artifacts
        json["presentationGraph"] = graph

        XCTAssertThrowsError(
            try ModelManifest.decode(JSONSerialization.data(withJSONObject: json))
        )
    }

    func testV3StrictDecodeRejectsMissingRequiredStructure() throws {
        var json = try fixtureJSON()
        var graph = try presentationGraph(in: json)
        var artifacts = try XCTUnwrap(graph["artifacts"] as? [[String: Any]])
        artifacts[0].removeValue(forKey: "compatibility")
        graph["artifacts"] = artifacts
        json["presentationGraph"] = graph

        XCTAssertThrowsError(
            try ModelManifest.decode(JSONSerialization.data(withJSONObject: json))
        )
    }

    func testStrictDecodeRejectsUnsupportedManifestVersion() throws {
        var json = try fixtureJSON()
        json["manifestVersion"] = 4

        XCTAssertThrowsError(
            try ModelManifest.decode(JSONSerialization.data(withJSONObject: json))
        ) { error in
            XCTAssertEqual(
                error as? ModelManifestDecodingError,
                .unsupportedManifestVersion(4)
            )
        }
    }

    func testV2FixtureStillDecodesWithoutPresentationGraph() throws {
        let manifest = try ModelManifest.decode(try fixtureData("manifest.json"))

        XCTAssertEqual(manifest.manifestVersion, 1)
        XCTAssertNil(manifest.presentationGraph)
        XCTAssertNoThrow(try ProductionModelPolicy.validateProductionManifest(manifest))
    }

    private func assertGraphPolicyError(
        _ json: [String: Any],
        equals expected: ModelCatalogGraphValidationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNoThrow(
            try ModelManifest.decode(JSONSerialization.data(withJSONObject: json)),
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try ProductionModelPolicy.validateProductionManifest(
                ModelManifest.decode(JSONSerialization.data(withJSONObject: json))
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? ProductionModelPolicyError,
                .invalidPresentationGraph(expected),
                file: file,
                line: line
            )
        }
    }

    private func fixtureJSON() throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixtureData("manifest_v3.json"))
                as? [String: Any]
        )
    }

    private func presentationGraph(
        in json: [String: Any]
    ) throws -> [String: Any] {
        try XCTUnwrap(json["presentationGraph"] as? [String: Any])
    }

    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: nil,
                subdirectory: "Fixtures/Models"
            )
        )
        return try Data(contentsOf: url)
    }

    private func fixtureString(_ name: String) throws -> String {
        String(decoding: try fixtureData(name), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
