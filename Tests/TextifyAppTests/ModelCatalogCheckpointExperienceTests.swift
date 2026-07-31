import Foundation
import TextifyModels
import XCTest

@testable import Textify

final class ModelCatalogCheckpointExperienceTests: XCTestCase {
    func testProjectionPresentsOneRowPerCheckpointInsteadOfOneRowPerArtifact() throws {
        let presentation = try makePresentation()

        XCTAssertEqual(
            presentation.rows.map(\.checkpointID).count,
            Set(presentation.rows.map(\.checkpointID)).count
        )
        let turbo = try XCTUnwrap(
            presentation.rows.first {
                $0.checkpointID
                    == "checkpoint.openai.whisper-large-v3-turbo"
            }
        )
        XCTAssertEqual(turbo.versionCount, 2)
        XCTAssertEqual(turbo.versionRoute, .popover)
    }

    func testScrollingSurfaceHasNoLazyOrPerRowFocusGraph() throws {
        let source = try String(
            contentsOf:
                repositoryRoot
                .appendingPathComponent(
                    "Sources/Textify/SettingsUI/ModelCatalogCheckpointView.swift"
                ),
            encoding: .utf8
        )
        let surfaceStart = try XCTUnwrap(
            source.range(of: "struct ModelCheckpointCatalogSurface")
        )
        let surfaceEnd = try XCTUnwrap(
            source.range(
                of: "private struct ModelCheckpointColumnHeader",
                range: surfaceStart.upperBound..<source.endIndex
            )
        )
        let surface = source[
            surfaceStart.lowerBound..<surfaceEnd.lowerBound
        ]

        XCTAssertTrue(surface.contains("VStack(spacing: 0)"))
        XCTAssertFalse(surface.contains("LazyVStack"))
        XCTAssertFalse(source.contains(".accessibilityFocused("))
        XCTAssertTrue(source.contains("ModelCheckpointProviderMark("))
        XCTAssertTrue(surface.contains(".focused(keyboardFocus)"))
        XCTAssertTrue(
            surface.contains(
                "}\n            .id(layoutMode)\n        }"
            ),
            "Responsive mode changes must recreate the complete section subtree."
        )
        XCTAssertFalse(
            surface.contains(
                ".id(layoutMode)\n                    .id(ModelCatalogHierarchyRowID.checkpoint"
            ),
            "Per-row identity allowed rows to retain a stale stacked layout."
        )
    }

    func testActiveCheckpointIsFirstAndExactlyOneOtherCheckpointIsRecommended() throws {
        let activeArtifactID = "ggml-small.en-q5_1"
        let presentation = try makePresentation(
            installedArtifactIDs: [activeArtifactID],
            activeArtifactID: activeArtifactID
        )

        XCTAssertEqual(
            presentation.rows.first?.checkpointID,
            "checkpoint.openai.whisper-small-en"
        )
        XCTAssertEqual(
            presentation.rows.filter { $0.annotation == .recommended }.count,
            1
        )
        XCTAssertEqual(presentation.rows.first?.annotation, .inUse)
        let activeAccessibilityLabel = try XCTUnwrap(
            presentation.rows.first?.accessibilityLabel(for: .wide)
        )
        XCTAssertTrue(activeAccessibilityLabel.contains("Installed"))
        XCTAssertFalse(activeAccessibilityLabel.contains("Not installed"))
    }

    func testRecommendationAnnotationIsSuppressedWhenRecommendedCheckpointIsActive() throws {
        let activeArtifactID = "parakeet-tdt-0.6b-v3"
        let presentation = try makePresentation(
            installedArtifactIDs: [activeArtifactID],
            activeArtifactID: activeArtifactID
        )

        XCTAssertEqual(presentation.rows.first?.annotation, .inUse)
        XCTAssertFalse(
            presentation.rows.contains { $0.annotation == .recommended }
        )
    }

    func testLanguageFilterKeepsActiveCheckpointAndBrowseAllRestoresCatalog() throws {
        let activeArtifactID = "paraformer-large-zh-int8"
        let english = try makePresentation(
            selectedLanguage: "en",
            installedArtifactIDs: [activeArtifactID],
            activeArtifactID: activeArtifactID
        )
        let all = try makePresentation(
            selectedLanguage: "en",
            browseAllLanguages: true,
            installedArtifactIDs: [activeArtifactID],
            activeArtifactID: activeArtifactID
        )

        XCTAssertEqual(english.rows.first?.selectedArtifactID, activeArtifactID)
        XCTAssertLessThan(english.rows.count, all.rows.count)
        XCTAssertTrue(
            english.rows.allSatisfy {
                $0.isActive || $0.supports(language: "en")
            }
        )
    }

    func testLanguageAwareDefaultUsesTheHindiCapableTurboArtifact() throws {
        let presentation = try makePresentation(selectedLanguage: "hi")
        let turbo = try XCTUnwrap(
            presentation.rows.first {
                $0.checkpointID
                    == "checkpoint.openai.whisper-large-v3-turbo"
            }
        )

        XCTAssertEqual(
            turbo.selectedArtifactID,
            "whisper-large-v3-turbo-q5_0"
        )
        XCTAssertNil(turbo.languageCompatibilityNote)
    }

    func testBrowseAllUseCanOfferASupportedLanguageWithoutChangingItSilently() throws {
        let presentation = try makePresentation(
            selectedLanguage: "en",
            browseAllLanguages: true
        )
        let chineseOnly = try XCTUnwrap(
            presentation.rows.first {
                $0.checkpointID
                    == "checkpoint.funasr.paraformer-large-zh"
            }
        )
        let mismatch = try XCTUnwrap(
            chineseOnly.languageMismatch(
                for: chineseOnly.selectedArtifact
            )
        )

        XCTAssertEqual(mismatch.requestedLanguageCode, "en")
        XCTAssertEqual(mismatch.supportedLanguageCode, "zh")
        XCTAssertNotNil(chineseOnly.languageCompatibilityNote)
    }

    func testVersionRoutingUsesNoControlPopoverAndDirectComparisonSheet() throws {
        let presentation = try makePresentation()
        let single = try XCTUnwrap(
            presentation.rows.first {
                $0.checkpointID == "checkpoint.openai.whisper-small-en"
            }
        )
        let two = try XCTUnwrap(
            presentation.rows.first {
                $0.checkpointID
                    == "checkpoint.openai.whisper-large-v3-turbo"
            }
        )
        let three = try XCTUnwrap(
            makePresentation(purpose: .voiceCleaning).rows.first {
                $0.checkpointID
                    == "checkpoint.alibaba.mossformer2-se-48k"
            }
        )
        let four = try XCTUnwrap(
            presentation.rows.first {
                $0.checkpointID
                    == "checkpoint.qwen.qwen3-asr-0.6b"
            }
        )
        let five = try XCTUnwrap(
            presentation.rows.first {
                $0.checkpointID
                    == "checkpoint.nvidia.parakeet-tdt-0.6b-v3"
            }
        )

        XCTAssertEqual(single.versionRoute, .none)
        XCTAssertEqual(two.versionRoute, .popover)
        XCTAssertEqual(three.versionRoute, .popover)
        XCTAssertEqual(four.versionRoute, .comparisonSheet)
        XCTAssertEqual(five.versionRoute, .comparisonSheet)
    }

    func testLegalManualOverrideSelectsArtifactAndIllegalOverrideFallsBackToSignedDefault() throws {
        let checkpointID = "checkpoint.openai.whisper-large-v3-turbo"
        let legalArtifactID = "whisper-large-v3-turbo-mlx"
        let legal = try makePresentation(
            artifactOverrides: [checkpointID: legalArtifactID]
        )
        let illegal = try makePresentation(
            artifactOverrides: [checkpointID: "missing-artifact"]
        )

        XCTAssertEqual(
            legal.rows.first { $0.checkpointID == checkpointID }?
                .selectedArtifactID,
            legalArtifactID
        )
        XCTAssertEqual(
            illegal.rows.first { $0.checkpointID == checkpointID }?
                .selectedArtifactID,
            "whisper-large-v3-turbo-q5_0"
        )
    }

    func testWideAndStackedExposeIdenticalFieldsAndAccessibilityLabel() throws {
        let row = try XCTUnwrap(makePresentation().rows.first)

        XCTAssertEqual(
            row.fields(for: .wide),
            row.fields(for: .stacked)
        )
        XCTAssertEqual(
            row.accessibilityLabel(for: .wide),
            row.accessibilityLabel(for: .stacked)
        )
    }

    func testLayoutPolicyUsesOneMeasuredThresholdWithHysteresis() {
        let metrics = ModelCheckpointLayoutMetrics.measured {
            $0 == "Not Comparable" ? 120 : 1
        }
        let policy = ModelCheckpointLayoutPolicy(metrics: metrics)
        let threshold = policy.requiredWideWidth

        XCTAssertEqual(metrics.qualityColumnFloor, 128)
        XCTAssertEqual(metrics.speedColumnFloor, 128)
        XCTAssertEqual(
            policy.mode(availableWidth: threshold - 1, previous: .wide),
            .stacked
        )
        XCTAssertEqual(
            policy.mode(
                availableWidth: threshold + 23,
                previous: .stacked
            ),
            .stacked
        )
        XCTAssertEqual(
            policy.mode(
                availableWidth: threshold + 24,
                previous: .stacked
            ),
            .wide
        )
    }

    func testShippingWindowWidthsKeepTheWholeCatalogInWideMode() {
        let policy = ModelCheckpointLayoutPolicy()
        let sidebarWidth: CGFloat = 258

        XCTAssertEqual(
            policy.mode(
                availableWidth: 1_060 - sidebarWidth,
                previous: .wide
            ),
            .wide
        )
        XCTAssertEqual(
            policy.mode(
                availableWidth: 1_080 - sidebarWidth,
                previous: .wide
            ),
            .wide
        )
    }

    func testInspectorCapacityTracksMeasuredCatalogWidth() {
        let compact = ModelCheckpointLayoutMetrics.measured { _ in 1 }
        let expanded = ModelCheckpointLayoutMetrics.measured {
            $0 == "Not Comparable" ? 160 : 1
        }
        let compactPolicy = ModelCheckpointInspectorLayoutPolicy(
            catalogLayoutPolicy: .init(metrics: compact),
            sidebarWidth: 258,
            inspectorWidth: 320,
            separation: 24
        )
        let expandedPolicy = ModelCheckpointInspectorLayoutPolicy(
            catalogLayoutPolicy: .init(metrics: expanded),
            sidebarWidth: 258,
            inspectorWidth: 320,
            separation: 24
        )

        XCTAssertGreaterThan(
            expandedPolicy.requiredTrailingWindowWidth,
            compactPolicy.requiredTrailingWindowWidth
        )
        XCTAssertFalse(
            expandedPolicy.usesTrailingInspector(
                windowWidth: compactPolicy.requiredTrailingWindowWidth
            )
        )
    }

    func testSearchRanksAnExactCheckpointNameAheadOfCuratedOrder() throws {
        let rows = try makePresentation(
            browseAllLanguages: true
        ).rows
        let first = try XCTUnwrap(rows.first)
        let later = try XCTUnwrap(
            rows.dropFirst().first { $0.title != first.title }
        )
        let query = later.title.lowercased()

        XCTAssertLessThan(
            ModelCheckpointListPresentation.searchRank(
                later,
                normalizedQuery: query
            ),
            ModelCheckpointListPresentation.searchRank(
                first,
                normalizedQuery: query
            )
        )
    }

    func testStableOrderKeepsNewlyActiveCheckpointInPlaceUntilReentry() throws {
        let initial = try makePresentation()
        let artifactID = "ggml-small.en-q5_1"
        let checkpointID = "checkpoint.openai.whisper-small-en"
        let stableOrder = initial.rows.map(\.id)
        let activated = try makePresentation(
            installedArtifactIDs: [artifactID],
            activeArtifactID: artifactID,
            stableCheckpointOrder: stableOrder
        )

        XCTAssertEqual(activated.rows.map(\.id), stableOrder)
        XCTAssertEqual(
            activated.rows.first { $0.id == checkpointID }?.annotation,
            .inUse
        )
        XCTAssertNotEqual(activated.rows.first?.id, checkpointID)
    }

    func testVersionOptionsPutSignedRecommendationFirstAndReuseComparableEvidence() throws {
        let presentation = try makePresentation()
        let parakeet = try XCTUnwrap(
            presentation.rows.first {
                $0.checkpointID
                    == "checkpoint.nvidia.parakeet-tdt-0.6b-v3"
            }
        )
        let comparisonByID = Dictionary(
            uniqueKeysWithValues: parakeet.checkpoint.variantComparisons.map {
                ($0.id, $0)
            }
        )

        XCTAssertTrue(parakeet.versionOptions.first?.isRecommended == true)
        for option in parakeet.versionOptions {
            XCTAssertEqual(
                option.quality,
                comparisonByID[option.id]?.quality
            )
            XCTAssertEqual(
                option.speed,
                comparisonByID[option.id]?.speed
            )
        }
    }

    func testScreenProjectionExposesFamilyCheckpointAndExactArtifactHierarchy()
        throws
    {
        let projection = ModelCatalogScreenProjection(
            try makePresentation()
        )
        let row = try XCTUnwrap(
            projection.rows.first {
                $0.versionCount > 1
            }
        )

        XCTAssertEqual(row.outlineLevel, 2)
        XCTAssertTrue(
            row.accessibilitySummary.contains("Family, level 1")
        )
        XCTAssertTrue(
            row.accessibilitySummary.contains("Checkpoint, level 2")
        )
        XCTAssertEqual(
            row.versionOptions.map(\.outlineLevel),
            Array(repeating: 3, count: row.versionCount)
        )
        XCTAssertTrue(
            row.versionOptions.allSatisfy {
                $0.accessibilitySummary.contains(
                    "Exact Artifact, level 3"
                )
            }
        )
    }

    func testVoiceCleanerVersionsDoNotInventComparableRatings() throws {
        let presentation = try makePresentation(
            purpose: .voiceCleaning,
            selectedLanguage: nil
        )
        let cleaner = try XCTUnwrap(presentation.rows.first)

        XCTAssertEqual(cleaner.versionCount, 3)
        XCTAssertTrue(
            cleaner.versionOptions.allSatisfy {
                $0.quality == .notComparable
                    && $0.speed == .notComparable
            }
        )
    }

    func testKeyboardNavigationMovesAcrossStableCheckpointRowsOnly() {
        let ids = (0..<23).map { "checkpoint-\($0)" }

        XCTAssertEqual(
            ModelCheckpointKeyboardNavigation.result(
                for: .moveDown,
                focusedCheckpointID: "checkpoint-4",
                checkpointIDs: ids
            ),
            .focus("checkpoint-5")
        )
        XCTAssertEqual(
            ModelCheckpointKeyboardNavigation.result(
                for: .pageDown,
                focusedCheckpointID: "checkpoint-4",
                checkpointIDs: ids,
                pageSize: 8
            ),
            .focus("checkpoint-12")
        )
        XCTAssertEqual(
            ModelCheckpointKeyboardNavigation.result(
                for: .home,
                focusedCheckpointID: "checkpoint-12",
                checkpointIDs: ids
            ),
            .focus("checkpoint-0")
        )
        XCTAssertEqual(
            ModelCheckpointKeyboardNavigation.result(
                for: .end,
                focusedCheckpointID: "checkpoint-12",
                checkpointIDs: ids
            ),
            .focus("checkpoint-22")
        )
        XCTAssertEqual(
            ModelCheckpointKeyboardNavigation.result(
                for: .activate,
                focusedCheckpointID: "checkpoint-12",
                checkpointIDs: ids
            ),
            .inspect("checkpoint-12")
        )
    }

    func testKeyboardNavigationRoutesProgressiveExactArtifactDisclosure()
    {
        let ids = ["checkpoint-a", "checkpoint-b"]

        XCTAssertEqual(
            ModelCheckpointKeyboardNavigation.result(
                for: .expand,
                focusedCheckpointID: "checkpoint-a",
                checkpointIDs: ids,
                expandableCheckpointIDs: ["checkpoint-a"]
            ),
            .expand("checkpoint-a")
        )
        XCTAssertEqual(
            ModelCheckpointKeyboardNavigation.result(
                for: .collapse,
                focusedCheckpointID: "checkpoint-a",
                checkpointIDs: ids,
                expandedCheckpointID: "checkpoint-a",
                expandableCheckpointIDs: ["checkpoint-a"]
            ),
            .collapse("checkpoint-a")
        )
        XCTAssertEqual(
            ModelCheckpointKeyboardNavigation.result(
                for: .activate,
                focusedCheckpointID: "checkpoint-a",
                checkpointIDs: ids,
                inspectionArtifactID: "artifact-a"
            ),
            .inspectArtifact("artifact-a")
        )
    }

    func testDeletionPolicyRequiresOneExplicitInstalledMeasuredExactArtifact()
    {
        let candidates = [
            ModelCheckpointDeletionCandidate(
                checkpointID: "checkpoint-a",
                artifactID: "artifact-installed",
                isInstalled: true,
                hasMeasuredLocalSize: true,
                allowsDeletion: true
            ),
            ModelCheckpointDeletionCandidate(
                checkpointID: "checkpoint-a",
                artifactID: "artifact-size-pending",
                isInstalled: true,
                hasMeasuredLocalSize: false,
                allowsDeletion: true
            ),
            ModelCheckpointDeletionCandidate(
                checkpointID: "checkpoint-a",
                artifactID: "artifact-not-installed",
                isInstalled: false,
                hasMeasuredLocalSize: false,
                allowsDeletion: false
            ),
        ]

        XCTAssertNil(
            ModelCheckpointDeletionPolicy.artifactID(
                explicitlySelectedArtifactID: nil,
                focusedCheckpointID: "checkpoint-a",
                candidates: candidates
            ),
            "A Checkpoint's presented version is not an explicit Exact Artifact selection."
        )
        XCTAssertNil(
            ModelCheckpointDeletionPolicy.artifactID(
                explicitlySelectedArtifactID: "artifact-size-pending",
                focusedCheckpointID: "checkpoint-a",
                candidates: candidates
            )
        )
        XCTAssertNil(
            ModelCheckpointDeletionPolicy.artifactID(
                explicitlySelectedArtifactID: "artifact-installed",
                focusedCheckpointID: "checkpoint-b",
                candidates: candidates
            )
        )
        XCTAssertEqual(
            ModelCheckpointDeletionPolicy.artifactID(
                explicitlySelectedArtifactID: "artifact-installed",
                focusedCheckpointID: "checkpoint-a",
                candidates: candidates
            ),
            "artifact-installed"
        )
    }

    func testCommandDeleteNeverResolvesASelectedCheckpointImplicitly() {
        let ids = ["checkpoint-a"]

        XCTAssertEqual(
            ModelCheckpointKeyboardNavigation.result(
                for: .deleteSelection,
                focusedCheckpointID: "checkpoint-a",
                checkpointIDs: ids
            ),
            .ignored
        )
        XCTAssertEqual(
            ModelCheckpointKeyboardNavigation.result(
                for: .deleteSelection,
                focusedCheckpointID: "checkpoint-a",
                checkpointIDs: ids,
                deletionArtifactID: "artifact-installed"
            ),
            .deleteArtifact("artifact-installed")
        )
    }

    func testAccessibilityVisualPolicyMakesTheRequiredDecisionsExplicit() {
        let increaseContrast = ModelCheckpointAccessibilityVisualPolicy(
            increaseContrast: true,
            differentiateWithoutColor: false,
            reduceTransparency: false
        )
        XCTAssertTrue(increaseContrast.emphasizesSelectionBoundaries)
        XCTAssertTrue(increaseContrast.emphasizesControlBoundaries)
        XCTAssertFalse(increaseContrast.usesOpaqueSurfaces)

        let differentiate = ModelCheckpointAccessibilityVisualPolicy(
            increaseContrast: false,
            differentiateWithoutColor: true,
            reduceTransparency: false
        )
        XCTAssertTrue(differentiate.emphasizesSelectionBoundaries)
        XCTAssertTrue(differentiate.emphasizesControlBoundaries)

        let reduceTransparency = ModelCheckpointAccessibilityVisualPolicy(
            increaseContrast: false,
            differentiateWithoutColor: false,
            reduceTransparency: true
        )
        XCTAssertTrue(reduceTransparency.usesOpaqueSurfaces)
    }

    func testCheckpointInspectorPresentsExactSourceAndBundledLicense()
        throws
    {
        let presentation = try makePresentation()
        let row = try XCTUnwrap(
            presentation.rows.first {
                $0.checkpointID
                    == "checkpoint.openai.whisper-small-en"
            }
        )
        XCTAssertEqual(row.selectedArtifact.id, "ggml-small.en-q5_1")

        let sourceLicense = try XCTUnwrap(
            ModelCheckpointInspectorSourceLicensePresentation(
                artifact: row.selectedArtifact
            )
        )
        XCTAssertEqual(
            sourceLicense.upstreamSourceURL,
            URL(string: "https://huggingface.co/ggerganov/whisper.cpp")
        )
        XCTAssertEqual(
            sourceLicense.sourceAndLicense.sourceURL,
            sourceLicense.upstreamSourceURL
        )
        XCTAssertEqual(
            sourceLicense.sourceAndLicense.licenses,
            [
                ModelSourceLicensePresentation.License(
                    scope:
                        "OpenAI Whisper small.en model converted to ggml format",
                    spdxID: "MIT",
                    name: "MIT License",
                    licenseTextURL:
                        "https://github.com/Player0109/Textify/releases/download/models-v1/ggml-small.en-q5_1.LICENSES.txt"
                )
            ]
        )
        let license = try XCTUnwrap(
            sourceLicense.sourceAndLicense.licenses.first
        )
        XCTAssertEqual(
            BundledModelLicenseResourceResolver.resourceName(
                for: license.licenseTextURL
            ),
            "ggml-small.en-q5_1.LICENSES.txt"
        )
    }

    func testFamilyHeadingAppearsOnlyForTwoOrMoreVisibleCheckpoints() throws {
        let presentation = try makePresentation(selectedLanguage: "ja")

        XCTAssertTrue(
            presentation.sections.allSatisfy {
                $0.title == nil || $0.rows.count >= 2
            }
        )
    }

    func testStandaloneInstalledArtifactsRemainReachableOutsideTheSignedGraph()
        throws
    {
        let manifest = try ModelManifest.decode(
            Data(
                contentsOf:
                    repositoryRoot
                    .appendingPathComponent("models/manifest.json")
            )
        )
        let checksum = String(repeating: "a", count: 64)
        let custom = ModelEntry(
            id: "legacy",
            displayName: "Legacy Whisper",
            tier: "experimental",
            description: "Imported local model",
            sizeBytes: 100,
            files: [
                ModelFile(
                    filename: "legacy.gguf",
                    url: "https://example.com/legacy.gguf",
                    sha256: checksum,
                    sizeBytes: 100
                )
            ],
            licenses: [
                ModelLicense(
                    scope: "model",
                    spdxId: "MIT",
                    name: "MIT",
                    licenseTextUrl: "https://example.com/license"
                )
            ],
            provenance: ModelProvenance(
                sourceName: "Fixture",
                sourceUrl: "https://example.com/source",
                sourceRevision: String(repeating: "b", count: 40),
                sourceFile: "legacy.gguf",
                originalModelName: "Legacy Whisper",
                originalModelUrl: "https://example.com/model",
                mirroredBy: "Fixture",
                mirroredAt: "2026-07-27T00:00:00Z"
            ),
            runtimeParameters: .legacyEnglishWhisper,
            hallucinationThresholds: HallucinationThresholds(
                noSpeechProbabilityMax: 0.6,
                avgLogProbabilityMin: -1,
                compressionRatioMax: 2.4
            ),
            minAppVersion: "1.0.0"
        )
        let experience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: [installed(custom)],
            activePreferences: .init(
                transcriptionModelID: nil,
                voiceCleaningModelID: nil
            ),
            transferState: nil,
            query: ModelCatalogQuery(purpose: .transcription)
        )

        XCTAssertEqual(
            ModelCheckpointListPresentation
                .standaloneInstalledRows(in: experience)
                .map(\.id),
            [custom.id]
        )
    }

    private func makePresentation(
        purpose: ModelPurpose = .transcription,
        selectedLanguage: String? = "en",
        browseAllLanguages: Bool = false,
        installedArtifactIDs: Set<String> = [],
        activeArtifactID: String? = nil,
        artifactOverrides: [String: String] = [:],
        stableCheckpointOrder: [String] = [],
        searchText: String = ""
    ) throws -> ModelCheckpointListPresentation {
        let manifest = try ModelManifest.decode(
            Data(
                contentsOf:
                    repositoryRoot
                    .appendingPathComponent("models/manifest.json")
            )
        )
        let modelsByID = Dictionary(
            uniqueKeysWithValues: manifest.models.map { ($0.id, $0) }
        )
        let installedRecords = try installedArtifactIDs.map {
            installed(try XCTUnwrap(modelsByID[$0]))
        }
        var query = ModelCatalogQuery(purpose: purpose)
        query.searchText = searchText
        let experience = ModelCatalogExperience(
            trustedManifest: manifest,
            installedRecords: installedRecords,
            activePreferences: ModelCatalogActivePreferences(
                transcriptionModelID:
                    purpose == .transcription ? activeArtifactID : nil,
                voiceCleaningModelID:
                    purpose == .voiceCleaning ? activeArtifactID : nil
            ),
            transferState: nil,
            query: query
        )

        return ModelCheckpointListPresentation(
            experience: experience,
            purpose: purpose,
            selectedLanguage: selectedLanguage,
            browseAllLanguages: browseAllLanguages,
            searchText: searchText,
            artifactOverrides: artifactOverrides,
            stableCheckpointOrder: stableCheckpointOrder
        )
    }

    private func installed(_ model: ModelEntry) -> InstalledModelRecord {
        InstalledModelRecord(
            model: model,
            installedAt: "2026-07-27T00:00:00Z",
            localFilesByManifestFilename: Dictionary(
                uniqueKeysWithValues: model.files.map {
                    (
                        $0.filename,
                        "/tmp/\(model.id)/\($0.relativePath ?? $0.filename)"
                    )
                }
            )
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
