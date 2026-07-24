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

    func testV3StrictDecodeRejectsMissingFamilyProvider() throws {
        var json = try fixtureJSON()
        var graph = try presentationGraph(in: json)
        var families = try XCTUnwrap(graph["families"] as? [[String: Any]])
        var presentation = try XCTUnwrap(
            families[0]["presentation"] as? [String: Any]
        )
        presentation.removeValue(forKey: "provider")
        families[0]["presentation"] = presentation
        graph["families"] = families
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

    func testCompatibilityResolverUsesSignedAppSystemArchitectureAndMemoryRequirements() throws {
        let manifest = try ModelManifest.decode(try fixtureData("manifest_v3.json"))
        func compatibleIDs(
            appVersion: String = "1.1.0",
            macOSVersion: String = "14.0.0",
            physicalMemoryBytes: Int64 = 8_589_934_592
        ) throws -> Set<String> {
            try XCTUnwrap(
                ModelCatalogCompatibilityResolver(
                    context: ModelCatalogCompatibilityContext(
                        appVersion: appVersion,
                        macOSVersion: macOSVersion,
                        architecture: .arm64,
                        physicalMemoryBytes: physicalMemoryBytes
                    )
                ).compatibleModelIDs(in: manifest)
            )
        }

        XCTAssertEqual(
            try compatibleIDs(),
            ["whisper-small-q5_1", "whisper-small-q8_0", "whisper-tiny-f16"]
        )
        XCTAssertEqual(
            try compatibleIDs(physicalMemoryBytes: 536_870_912),
            ["whisper-tiny-f16"]
        )
        XCTAssertTrue(try compatibleIDs(appVersion: "1.0.9").isEmpty)
        XCTAssertTrue(try compatibleIDs(macOSVersion: "13.6.9").isEmpty)
    }

    func testCompatibilityResolverReturnsTypedConstraintOutcomes() throws {
        let manifest = try ModelManifest.decode(try fixtureData("manifest_v3.json"))
        let modelID = "whisper-small-q5_1"

        func compatibility(
            appVersion: String = "1.1.0",
            macOSVersion: String = "14.0.0",
            architecture: ModelArchitecture? = .arm64,
            physicalMemoryBytes: Int64 = 8_589_934_592,
            supportedRuntimes: [TranscriptionEngine] = TranscriptionEngine.allCases,
            supportedArtifactLayouts: [ModelArtifactLayout] = ModelArtifactLayout.allCases,
            supportedComputeRoutes: [ModelComputeRoute] = ModelComputeRoute.allCases
        ) -> ModelCatalogCompatibility {
            ModelCatalogCompatibilityResolver(
                context: ModelCatalogCompatibilityContext(
                    appVersion: appVersion,
                    macOSVersion: macOSVersion,
                    architecture: architecture,
                    physicalMemoryBytes: physicalMemoryBytes,
                    supportedRuntimes: supportedRuntimes,
                    supportedArtifactLayouts: supportedArtifactLayouts,
                    supportedComputeRoutes: supportedComputeRoutes
                )
            ).compatibility(for: modelID, in: manifest)
        }

        XCTAssertEqual(compatibility(), .compatible)
        XCTAssertEqual(
            compatibility(appVersion: "1.0.9"),
            .requiresAppUpdate(minimumVersion: "1.1.0")
        )
        XCTAssertEqual(
            compatibility(macOSVersion: "13.6.9"),
            .requiresMacOSUpdate(minimumVersion: "14.0.0")
        )
        XCTAssertEqual(
            compatibility(architecture: nil),
            .incompatible(
                .unsupportedArchitecture(
                    current: nil,
                    supported: [.arm64]
                )
            )
        )
        XCTAssertEqual(
            compatibility(physicalMemoryBytes: 536_870_912),
            .incompatible(
                .insufficientMemory(
                    requiredBytes: 1_073_741_824,
                    availableBytes: 536_870_912
                )
            )
        )
        XCTAssertEqual(
            compatibility(supportedRuntimes: []),
            .incompatible(.unsupportedRuntime(.whisperCpp))
        )
        XCTAssertEqual(
            compatibility(supportedArtifactLayouts: []),
            .incompatible(.unsupportedArtifactLayout(.singleFile))
        )
        XCTAssertEqual(
            compatibility(supportedComputeRoutes: []),
            .incompatible(.unsupportedComputeRoute(.gpuViaMetal))
        )
        XCTAssertEqual(
            compatibility(appVersion: "development"),
            .indeterminate(.invalidCurrentAppVersion("development"))
        )
    }

    func testCompatibilityResolverPreservesSignedLegacyCatalogOperations() throws {
        let manifest = try ModelManifest.decode(try fixtureData("manifest.json"))
        let modelID = try XCTUnwrap(manifest.models.first?.id)
        let resolver = ModelCatalogCompatibilityResolver(
            context: ModelCatalogCompatibilityContext(
                appVersion: "1.1.0",
                macOSVersion: "14.0.0",
                architecture: .arm64,
                physicalMemoryBytes: 8_589_934_592
            )
        )

        XCTAssertEqual(
            resolver.compatibility(for: modelID, in: manifest),
            .compatible
        )
        XCTAssertEqual(resolver.compatibleModelIDs(in: manifest), [modelID])
    }

    func testCheckpointFallbackUsesSignedOrderOnlyForDeterministicIncompatibility() throws {
        var json = try fixtureJSON()
        var graph = try presentationGraph(in: json)
        var artifacts = try XCTUnwrap(graph["artifacts"] as? [[String: Any]])
        var recommendedCompatibility = try XCTUnwrap(
            artifacts[0]["compatibility"] as? [String: Any]
        )
        recommendedCompatibility["minimumMemoryBytes"] = 16_000_000_000
        artifacts[0]["compatibility"] = recommendedCompatibility
        graph["artifacts"] = artifacts
        json["presentationGraph"] = graph
        let manifest = try ModelManifest.decode(
            JSONSerialization.data(withJSONObject: json)
        )

        let resolver = ModelCatalogCompatibilityResolver(
            context: ModelCatalogCompatibilityContext(
                appVersion: "1.1.0",
                macOSVersion: "14.0.0",
                architecture: .arm64,
                physicalMemoryBytes: 8_000_000_000
            )
        )
        let resolution = try XCTUnwrap(
            resolver.checkpointResolution(
                for: "checkpoint.whisper.small",
                in: manifest
            )
        )

        XCTAssertEqual(resolution.recommendedArtifactID, "whisper-small-q5_1")
        XCTAssertEqual(
            resolution.recommendedCompatibility,
            .incompatible(
                .insufficientMemory(
                    requiredBytes: 16_000_000_000,
                    availableBytes: 8_000_000_000
                )
            )
        )
        XCTAssertEqual(resolution.installArtifactID, "whisper-small-q8_0")
        XCTAssertEqual(
            resolution.fallback,
            ModelCatalogFallbackResolution(
                recommendedArtifactID: "whisper-small-q5_1",
                fallbackArtifactID: "whisper-small-q8_0"
            )
        )

        let updateRequired = ModelCatalogCompatibilityResolver(
            context: ModelCatalogCompatibilityContext(
                appVersion: "1.0.9",
                macOSVersion: "14.0.0",
                architecture: .arm64,
                physicalMemoryBytes: 8_000_000_000
            )
        ).checkpointResolution(
            for: "checkpoint.whisper.small",
            in: manifest
        )
        XCTAssertEqual(
            updateRequired?.recommendedCompatibility,
            .requiresAppUpdate(minimumVersion: "1.1.0")
        )
        XCTAssertNil(updateRequired?.installArtifactID)
        XCTAssertNil(updateRequired?.fallback)
    }

    func testCompatibilityResolverHasNoAuthorityWithoutATrustedManifest() {
        let resolver = ModelCatalogCompatibilityResolver(
            context: ModelCatalogCompatibilityContext(
                appVersion: "1.1.0",
                macOSVersion: "14.0.0",
                architecture: .arm64,
                physicalMemoryBytes: 8_589_934_592
            )
        )

        XCTAssertNil(resolver.compatibleModelIDs(in: nil))
        XCTAssertEqual(
            resolver.compatibility(for: "missing", in: nil),
            .indeterminate(.trustedManifestUnavailable)
        )
    }

    func testV3AliasRejectsUnknownCanonicalArtifact() throws {
        var json = try fixtureJSON()
        json["artifactAliases"] = [
            [
                "aliasArtifactID": "whisper-small-q5_1",
                "canonicalArtifactID": "missing-artifact",
            ],
        ]
        let manifest = try ModelManifest.decode(
            JSONSerialization.data(withJSONObject: json)
        )

        XCTAssertThrowsError(
            try ProductionModelPolicy.validateProductionManifest(manifest)
        ) { error in
            XCTAssertEqual(
                error as? ProductionModelPolicyError,
                .invalidArtifactAlias(
                    .missingArtifact("missing-artifact")
                )
            )
        }
    }

    func testV3AliasRejectsSelfAlias() throws {
        var json = try fixtureJSON()
        let models = try XCTUnwrap(json["models"] as? [[String: Any]])
        let artifactID = try XCTUnwrap(models[0]["id"] as? String)
        json["artifactAliases"] = [
            [
                "aliasArtifactID": artifactID,
                "canonicalArtifactID": artifactID,
            ],
        ]

        assertAliasPolicyError(
            json,
            equals: .selfAlias(artifactID)
        )
    }

    func testV3AliasRejectsDuplicateAliasIdentity() throws {
        var json = try fixtureJSON()
        let models = try XCTUnwrap(json["models"] as? [[String: Any]])
        let aliasID = try XCTUnwrap(models[0]["id"] as? String)
        let canonicalID = try XCTUnwrap(models[1]["id"] as? String)
        json["artifactAliases"] = [
            [
                "aliasArtifactID": aliasID,
                "canonicalArtifactID": canonicalID,
            ],
            [
                "aliasArtifactID": aliasID,
                "canonicalArtifactID": canonicalID,
            ],
        ]

        assertAliasPolicyError(
            json,
            equals: .duplicateAlias(aliasID)
        )
    }

    func testV3AliasRejectsAliasChain() throws {
        var json = try fixtureJSON()
        let models = try XCTUnwrap(json["models"] as? [[String: Any]])
        let firstID = try XCTUnwrap(models[0]["id"] as? String)
        let secondID = try XCTUnwrap(models[1]["id"] as? String)
        let thirdID = try XCTUnwrap(models[2]["id"] as? String)
        json["artifactAliases"] = [
            [
                "aliasArtifactID": firstID,
                "canonicalArtifactID": secondID,
            ],
            [
                "aliasArtifactID": secondID,
                "canonicalArtifactID": thirdID,
            ],
        ]

        assertAliasPolicyError(
            json,
            equals: .canonicalArtifactIsAlias(secondID)
        )
    }

    func testV3AliasRejectsDigestMismatch() throws {
        var json = try fixtureJSON()
        var models = try XCTUnwrap(json["models"] as? [[String: Any]])
        let aliasID = try XCTUnwrap(models[0]["id"] as? String)
        let canonicalID = try XCTUnwrap(models[1]["id"] as? String)
        var canonicalModel = models[1]
        var files = try XCTUnwrap(
            canonicalModel["files"] as? [[String: Any]]
        )
        files[0]["sha256"] = String(repeating: "f", count: 64)
        canonicalModel["files"] = files
        models[1] = canonicalModel
        json["models"] = models
        json["artifactAliases"] = [
            [
                "aliasArtifactID": aliasID,
                "canonicalArtifactID": canonicalID,
            ],
        ]

        assertAliasPolicyError(
            json,
            equals: .digestMismatch(
                aliasArtifactID: aliasID,
                canonicalArtifactID: canonicalID
            )
        )
    }

    func testV3AliasMayDesignateCanonicalIdentityForEqualTypedDigest() throws {
        var json = try fixtureJSON()
        var models = try XCTUnwrap(json["models"] as? [[String: Any]])
        var aliasModel = models[0]
        aliasModel["id"] = "whisper-small-q5_1-alias"
        models.append(aliasModel)
        json["models"] = models

        var graph = try presentationGraph(in: json)
        var artifacts = try XCTUnwrap(graph["artifacts"] as? [[String: Any]])
        var aliasArtifact = artifacts[0]
        aliasArtifact["id"] = "whisper-small-q5_1-alias"
        var aliasPresentation = try XCTUnwrap(
            aliasArtifact["presentation"] as? [String: Any]
        )
        aliasPresentation["curatedRank"] = 99
        aliasArtifact["presentation"] = aliasPresentation
        artifacts.append(aliasArtifact)
        graph["artifacts"] = artifacts
        var checkpoints = try XCTUnwrap(
            graph["checkpoints"] as? [[String: Any]]
        )
        var artifactIDs = try XCTUnwrap(
            checkpoints[0]["artifactIDs"] as? [String]
        )
        artifactIDs.append("whisper-small-q5_1-alias")
        checkpoints[0]["artifactIDs"] = artifactIDs
        graph["checkpoints"] = checkpoints
        json["presentationGraph"] = graph
        json["artifactAliases"] = [
            [
                "aliasArtifactID": "whisper-small-q5_1-alias",
                "canonicalArtifactID": "whisper-small-q5_1",
            ],
        ]

        let manifest = try ModelManifest.decode(
            JSONSerialization.data(withJSONObject: json)
        )
        XCTAssertNoThrow(
            try ProductionModelPolicy.validateProductionManifest(manifest)
        )
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

    private func assertAliasPolicyError(
        _ json: [String: Any],
        equals expected: ModelArtifactAliasValidationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try ProductionModelPolicy.validateProductionManifest(
                ModelManifest.decode(
                    JSONSerialization.data(withJSONObject: json)
                )
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? ProductionModelPolicyError,
                .invalidArtifactAlias(expected),
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
