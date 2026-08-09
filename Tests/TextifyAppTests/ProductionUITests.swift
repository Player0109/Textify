@testable import Textify
import AppKit
import TextifyModels
import TextifyRuntime
import TextifySettings
import XCTest

final class ProductionUITests: XCTestCase {
    func testLaunchPolicyShowsOnboardingWithoutStartingRuntimeUntilSetupCompletes() {
        var preferences = AppPreferences.defaults
        preferences.onboardingCompleted = false

        XCTAssertEqual(AppLaunchPolicy.action(for: preferences), .showOnboarding)

        preferences.onboardingCompleted = true

        XCTAssertEqual(AppLaunchPolicy.action(for: preferences), .startRuntime)
    }

    func testSettingsProductionPaneSetExcludesScaffoldPanes() {
        XCTAssertEqual(
            SettingsPane.productionVisiblePanes,
            [
                .general,
                .dictation,
                .transcriptionModels,
                .voiceCleaning,
                .privacy,
                .logs,
                .advanced,
            ]
        )
        XCTAssertEqual(SettingsPane.transcriptionModels.modelPurpose, .transcription)
        XCTAssertEqual(SettingsPane.voiceCleaning.modelPurpose, .voiceCleaning)
        XCTAssertEqual(SettingsPane.transcriptionModels.sidebarTitle, "Transcription Models")
        XCTAssertEqual(SettingsPane.voiceCleaning.sidebarTitle, "Voice Cleaning")
        XCTAssertEqual(SettingsPane.logs.sidebarTitle, "Logs")
        XCTAssertEqual(SettingsPane.logs.systemImage, "doc.text.magnifyingglass")
    }

    func testPurposeDestinationsHaveSpecificEmptyAndUnavailableRecoveryCopy() {
        XCTAssertEqual(
            ModelCatalogPurposeDestination.transcription.emptyTitle,
            "No transcription models are available"
        )
        XCTAssertEqual(
            ModelCatalogPurposeDestination.voiceCleaning.emptyTitle,
            "No voice-cleaning models are available"
        )
        XCTAssertEqual(
            ModelCatalogPurposeDestination.transcription.unavailableActionTitle,
            nil
        )
        XCTAssertTrue(
            ModelCatalogPurposeDestination.voiceCleaning.unavailableDetail
                .contains("optional")
        )
    }

    func testShippingModelManagementStringCatalogRetainsCriticalLabels() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Localizable.xcstrings")
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: catalogURL)
            ) as? [String: Any]
        )
        XCTAssertEqual(object["sourceLanguage"] as? String, "en")
        let strings = try XCTUnwrap(
            object["strings"] as? [String: Any]
        )
        let criticalLabels = [
            "Action",
            "Action column header",
            "About Model Variants…",
            "All",
            "Back to Filtered Results",
            "Cancel",
            "Clear Search",
            "Collapsed",
            "Delete",
            "Details",
            "Disable",
            "Dismiss Reveal",
            "Disclosure",
            "Downloads",
            "Enable",
            "Expanded",
            "Features",
            "Features column header",
            "Filters",
            "Hide Details",
            "Import Whisper Model…",
            "Installed",
            "Install",
            "Inspect",
            "Logical position",
            "Model",
            "Model catalog table headers",
            "Model column header",
            "More catalog actions",
            "No Downloads",
            "Outline level",
            "Pause",
            "Quality",
            "Quality column header",
            "Reinstall",
            "Remove Data",
            "Reset Catalog View",
            "Resume",
            "Retry",
            "Search models",
            "Show in Catalog",
            "Speed",
            "Speed column header",
            "State",
            "State column header",
            "Transcription Models",
            "Use Model",
            "Verify Integrity",
            "Verify Installed",
            "Voice Cleaning",
        ]

        for key in criticalLabels {
            let entry = try XCTUnwrap(
                strings[key] as? [String: Any],
                "Missing critical localization key \(key)"
            )
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any]
            )
            XCTAssertEqual(Set(localizations.keys), ["en"])
            let english = try XCTUnwrap(
                localizations["en"] as? [String: Any]
            )
            let unit = try XCTUnwrap(
                english["stringUnit"] as? [String: Any]
            )
            let value = try XCTUnwrap(unit["value"] as? String)
            XCTAssertFalse(value.isEmpty)
        }
    }

    func testVisualIdentitySupportsTheNativeSidebarRedesign() {
        XCTAssertEqual(TextifyVisualIdentity.signatureElement, "Spokenly blue selection")
        XCTAssertEqual(TextifyVisualIdentity.voiceVioletHex, "#0A84FF")
        XCTAssertEqual(TextifyWindowMetrics.mainWidth, 1_080)
        XCTAssertEqual(TextifyWindowMetrics.mainMinimumWidth, 1_060)
        XCTAssertEqual(TextifyWindowMetrics.sidebarWidth, 258)
        XCTAssertGreaterThan(TextifyWindowMetrics.mainWidth, TextifyWindowMetrics.mainMinimumWidth)
        XCTAssertGreaterThan(TextifyWindowMetrics.readableContentWidth, 720)
        XCTAssertGreaterThan(TextifyWindowMetrics.onboardingWidth, 680)
    }

    func testAccessibilityDragSourcePublishesALoadableApplicationBundleFileURL() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let appURL = temporaryDirectory.appendingPathComponent("Textify.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let item = TextifyAppDragSource.pasteboardItem(for: appURL)
        let representation = try XCTUnwrap(item.data(forType: .fileURL))
        let publishedURL = try XCTUnwrap(URL(dataRepresentation: representation, relativeTo: nil))

        XCTAssertEqual(item.types, [.fileURL])
        XCTAssertEqual(publishedURL.standardizedFileURL, appURL.standardizedFileURL)
    }

    @MainActor
    func testAccessibilityPermissionMonitorDetectsAnExternalStateChange() async throws {
        var probeCount = 0
        let monitor = AccessibilityPermissionMonitor(
            wait: {},
            currentState: {
                probeCount += 1
                return probeCount < 3 ? .denied : .granted
            }
        )

        let state = try await monitor.nextChange(from: .denied)

        XCTAssertEqual(state, .granted)
        XCTAssertEqual(probeCount, 3)
    }

    func testGuidedPermissionSetupChoosesTheNextRecoverableAction() {
        let fresh = PermissionSetupPresentation(
            permissions: RuntimePermissionSnapshot(
                microphone: .unknown,
                accessibility: .denied,
                inputMonitoring: .granted
            )
        )
        XCTAssertEqual(
            fresh.primaryAction,
            .requestMicrophoneThenAccessibility
        )
        XCTAssertEqual(fresh.actionTitle, "Allow Permissions")
        XCTAssertEqual(fresh.completedCount, 0)

        let microphoneDenied = PermissionSetupPresentation(
            permissions: RuntimePermissionSnapshot(
                microphone: .denied,
                accessibility: .granted,
                inputMonitoring: .granted
            )
        )
        XCTAssertEqual(
            microphoneDenied.primaryAction,
            .openMicrophoneSettings
        )
        XCTAssertEqual(
            microphoneDenied.actionTitle,
            "Open Microphone Settings"
        )

        let accessibilityMissing = PermissionSetupPresentation(
            permissions: RuntimePermissionSnapshot(
                microphone: .granted,
                accessibility: .denied,
                inputMonitoring: .granted
            )
        )
        XCTAssertEqual(
            accessibilityMissing.primaryAction,
            .requestAccessibility
        )
        XCTAssertEqual(
            accessibilityMissing.actionTitle,
            "Allow Accessibility"
        )
        XCTAssertEqual(accessibilityMissing.completedCount, 1)

        let complete = PermissionSetupPresentation(
            permissions: RuntimePermissionSnapshot(
                microphone: .granted,
                accessibility: .granted,
                inputMonitoring: .denied
            )
        )
        XCTAssertEqual(complete.primaryAction, .complete)
        XCTAssertNil(complete.actionTitle)
        XCTAssertEqual(complete.completedCount, 2)
    }

    func testSetupStatusRoutesStraightToTheMissingRequirement() {
        let permissionsMissing = RuntimePermissionSnapshot(
            microphone: .granted,
            accessibility: .denied,
            inputMonitoring: .granted
        )
        let missingPermissionReadiness = ReadinessSnapshot(
            permissions: permissionsMissing,
            model: .noActiveModel
        )
        XCTAssertEqual(
            SettingsSetupNavigation.destination(
                for: missingPermissionReadiness
            ),
            .privacy
        )
        XCTAssertEqual(
            SettingsSetupNavigation.detail(for: missingPermissionReadiness),
            "Grant required permissions"
        )

        let permissionsReady = RuntimePermissionSnapshot(
            microphone: .granted,
            accessibility: .granted,
            inputMonitoring: .denied
        )
        let noModelReadiness = ReadinessSnapshot(
            permissions: permissionsReady,
            model: .noActiveModel
        )
        XCTAssertEqual(
            SettingsSetupNavigation.destination(for: noModelReadiness),
            .transcriptionModels
        )
        XCTAssertEqual(
            SettingsSetupNavigation.detail(for: noModelReadiness),
            "Choose a transcription model"
        )

        let loadingModelReadiness = ReadinessSnapshot(
            permissions: permissionsReady,
            model: .loading(modelID: "active-model")
        )
        XCTAssertEqual(
            SettingsSetupNavigation.detail(for: loadingModelReadiness),
            "Model setup is in progress"
        )

        let failedModelReadiness = ReadinessSnapshot(
            permissions: permissionsReady,
            model: .failed(
                modelID: "active-model",
                reason: .loadFailed
            )
        )
        XCTAssertEqual(
            SettingsSetupNavigation.detail(for: failedModelReadiness),
            "Repair the active model"
        )

        let revokedModelReadiness = ReadinessSnapshot(
            permissions: permissionsReady,
            model: .revoked(modelID: "active-model")
        )
        XCTAssertEqual(
            SettingsSetupNavigation.detail(for: revokedModelReadiness),
            "Replace the active model"
        )
    }

    func testSystemPrivacySettingsDestinationsOpenTheExpectedPanes() {
        XCTAssertEqual(
            SystemPrivacySettingsDestination.microphone.url.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
        XCTAssertEqual(
            SystemPrivacySettingsDestination.accessibility.url.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    func testModelCatalogDoesNotInferRatingsFromSupportTier() {
        let recommended = ProductionModelPresentation.v1_1

        XCTAssertEqual(recommended.qualitySignalLevel, 0)
        XCTAssertEqual(recommended.speedSignalLevel, 0)
        XCTAssertEqual(recommended.qualityLabel, "Unrated")
        XCTAssertEqual(recommended.speedLabel, "Unrated")
        XCTAssertNil(recommended.qualityScore)
        XCTAssertNil(recommended.speedScore)
        XCTAssertEqual(recommended.engineName, "Whisper.cpp")
        XCTAssertEqual(recommended.acceleratorName, "Metal GPU")
        XCTAssertEqual(recommended.languageDescription, "English")
        XCTAssertTrue(recommended.isCurated)

        let deprecated = ProductionModelPresentation(
            id: "installed-model",
            displayName: "Installed Model",
            description: "Installed locally.",
            details: nil,
            isCurated: false
        )
        XCTAssertFalse(deprecated.isCurated)
    }

    func testModelCatalogUsesCleanNamesAndRecognizableProviders() {
        XCTAssertEqual(ProductionModelPresentation.v1_1.catalogDisplayName, "Whisper small.en q5_1")
        XCTAssertEqual(ProductionModelPresentation.v1_1.provider, .openAI)

        let parakeetOnMLX = ProductionModelPresentation(
            id: "parakeet-mlx",
            displayName: "Experimental - Parakeet V3 MLX",
            description: "Community MLX conversion.",
            details: nil,
            engineName: "MLX Audio",
            sourceName: "mlx-community/parakeet-tdt-0.6b-v3"
        )
        XCTAssertEqual(parakeetOnMLX.catalogDisplayName, "Parakeet V3 MLX")
        XCTAssertEqual(parakeetOnMLX.provider, .nvidia)

        let cohere = ProductionModelPresentation(
            id: "cohere",
            displayName: "Cohere Transcribe",
            description: "Local speech model.",
            details: nil,
            sourceName: "community/cohere-transcribe"
        )
        XCTAssertEqual(cohere.catalogDisplayName, "Cohere Transcribe")
        XCTAssertEqual(cohere.provider, .cohere)

        let qwen = ProductionModelPresentation(
            id: "qwen",
            displayName: "Qwen3-ASR",
            description: "Local speech model.",
            details: nil,
            sourceName: "QwenLM/Qwen3-ASR"
        )
        XCTAssertEqual(qwen.provider, .qwen)

        let mossFormer = ProductionModelPresentation(
            id: "mossformer",
            displayName: "MossFormer2 SE",
            description: "Local speech enhancement model.",
            details: nil,
            sourceName: "alibabasglab/MossFormer2_SE_48K"
        )
        XCTAssertEqual(mossFormer.provider, .alibaba)

        let crisperWhisper = ProductionModelPresentation(
            id: "crisperwhisper-large",
            displayName: "Experimental - CrisperWhisper 2.0 Large F16",
            description: "Local speech model.",
            details: nil,
            engineName: "Whisper.cpp",
            sourceName: "drbaph/CrisperWhisper2.0-GGML"
        )
        XCTAssertEqual(crisperWhisper.provider, .nyra)
        XCTAssertEqual(
            ModelProviderIdentity.resolve(from: "Nyra Labs", "Whisper"),
            .nyra
        )
    }

    func testModelProvidersUseRecognizableVendorLogoAssets() {
        XCTAssertEqual(ModelProviderIdentity.openAI.logoAssetName, "VendorOpenAI")
        XCTAssertEqual(ModelProviderIdentity.nvidia.logoAssetName, "VendorNVIDIA")
        XCTAssertEqual(ModelProviderIdentity.cohere.logoAssetName, "VendorCohere")
        XCTAssertEqual(ModelProviderIdentity.qwen.logoAssetName, "VendorQwen")
        XCTAssertEqual(ModelProviderIdentity.alibaba.logoAssetName, "VendorAlibabaCloud")
        XCTAssertEqual(ModelProviderIdentity.reazon.logoAssetName, "VendorReazon")
        XCTAssertNil(ModelProviderIdentity.nyra.logoAssetName)
        XCTAssertEqual(ModelProviderIdentity.nyra.mark, "NY")
        XCTAssertNil(ModelProviderIdentity.apple.logoAssetName)
        XCTAssertEqual(ModelProviderIdentity.apple.systemImage, "apple.logo")
        XCTAssertNil(ModelProviderIdentity.community.logoAssetName)
    }

    func testModelCatalogExposesSignedBenchmarkEvidence() {
        let rating = benchmarkRating(
            modelID: "measured",
            qualityScore: 83,
            qualityLevel: 4,
            speedScore: 92,
            speedLevel: 5
        )
        let model = ProductionModelPresentation(
            id: "measured",
            displayName: "Measured",
            description: "Measured model.",
            details: nil,
            supportTier: "Experimental",
            benchmark: rating
        )

        XCTAssertEqual(model.qualityLabel, "High")
        XCTAssertEqual(model.speedLabel, "Fastest")
        XCTAssertEqual(model.qualityScore, 83)
        XCTAssertEqual(model.speedScore, 92)
        XCTAssertTrue(model.qualityEvidenceDescription?.contains("732 speech cases") == true)
        XCTAssertTrue(model.speedEvidenceDescription?.contains("p95 205 ms") == true)
        XCTAssertTrue(model.benchmarkPolicyDescription.contains("3 runs"))
        XCTAssertTrue(model.benchmarkPolicyDescription.contains("source cccccccccccc"))
    }

    func testBundledCatalogClassifiesMLXGGUFAndQuantizationMetadata() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifest = try ModelManifest.decode(
            Data(contentsOf: repositoryRoot.appendingPathComponent("models/manifest.json"))
        )

        func presentation(_ id: String) throws -> ProductionModelPresentation {
            ProductionModelPresentation(model: try XCTUnwrap(manifest.models.first { $0.id == id }))
        }

        let mlx8Bit = try presentation("qwen3-asr-0.6b-mlx-8bit")
        XCTAssertEqual(mlx8Bit.artifactFormat, .mlx)
        XCTAssertEqual(mlx8Bit.artifactPrecision, .eightBit)

        let gguf16Bit = try presentation("qwen3-asr-0.6b-bf16")
        XCTAssertEqual(gguf16Bit.artifactFormat, .gguf)
        XCTAssertEqual(gguf16Bit.artifactPrecision, .sixteenBit)

        XCTAssertEqual(
            try presentation("parakeet-tdt-0.6b-v3-q5-k-m").artifactPrecision,
            .fiveBit
        )
        XCTAssertEqual(
            try presentation("canary-qwen-2.5b-q4-k-m").artifactPrecision,
            .fourBit
        )
        XCTAssertEqual(
            try presentation("parakeet-tdt-0.6b-v2-mlx").artifactPrecision,
            .thirtyTwoBit
        )
        XCTAssertEqual(
            try presentation("mossformer2-se-fp32").artifactPrecision,
            .thirtyTwoBit
        )
        XCTAssertEqual(
            try presentation("mossformer2-se-fp16").artifactPrecision,
            .sixteenBit
        )
        XCTAssertEqual(
            try presentation("mossformer2-se-int8").artifactPrecision,
            .eightBit
        )
        XCTAssertEqual(
            try presentation("crisperwhisper-2-large-f16").artifactPrecision,
            .sixteenBit
        )
        XCTAssertEqual(
            try presentation("crisperwhisper-2-turbo-f16").artifactPrecision,
            .sixteenBit
        )
    }

    func testReadinessCopyExplainsTheHoldAndReleaseInteraction() {
        XCTAssertEqual(TextifyReadinessPresentation.title(canDictate: true), "Ready to dictate")
        XCTAssertEqual(
            TextifyReadinessPresentation.detail(canDictate: true, triggerName: "Right Command"),
            "Hold Right Command, speak, then release to type."
        )
        XCTAssertEqual(TextifyReadinessPresentation.title(canDictate: false), "Finish setup")
        XCTAssertEqual(
            TextifyReadinessPresentation.detail(canDictate: false, triggerName: "Right Command"),
            "Review Dictation, Transcription Models, and Privacy before your first dictation."
        )
    }

    func testHybridWindowPresentationUsesFirstClassOpenActionAndDockCopy() {
        XCTAssertEqual(MenuBarPresentation.openTextifyTitle, "Open Textify…")
        XCTAssertEqual(DockPreferencePresentation.title, "Keep Textify in the Dock")
    }

    func testExcludedAppsSettingsAddsByBundleIdentityWithoutDuplicates() {
        let candidate = ExcludedAppCandidate(
            bundleIdentifier: "com.example.Editor",
            displayName: "Editor",
            path: "/Applications/Editor.app"
        )

        let once = ExcludedAppsSettingsModel.adding(candidate, to: [])
        let twice = ExcludedAppsSettingsModel.adding(candidate, to: once)

        XCTAssertEqual(once.count, 1)
        XCTAssertEqual(twice, once)
        XCTAssertEqual(once.first?.bundleIdentifier, "com.example.Editor")
        XCTAssertEqual(once.first?.lastKnownPath, "/Applications/Editor.app")
    }

    @MainActor
    func testExcludedAppIconCacheIsGeneratedOnlyForTheSelectedAppAndIsBoundedPNG() throws {
        let candidate = ExcludedAppCandidate(
            bundleIdentifier: "com.example.Editor",
            displayName: "Editor",
            path: "/Applications/Editor.app"
        )
        let iconData = try XCTUnwrap(
            ExcludedAppsSettingsModel.compactIconData(
                for: URL(fileURLWithPath: "/Applications", isDirectory: true)
            )
        )

        let apps = ExcludedAppsSettingsModel.adding(
            candidate,
            to: [],
            cachedIconData: iconData
        )

        XCTAssertTrue(iconData.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        XCTAssertLessThan(iconData.count, 128 * 1_024)
        XCTAssertEqual(apps.first?.cachedIconData, iconData)
    }

    func testMenuStatusAndBlockerSummariesAreProductionSafe() {
        XCTAssertEqual(DictationRuntimeStatus.idle.menuStatusTitle, "Ready")
        XCTAssertEqual(DictationRuntimeStatus.waitingForActivation.menuStatusTitle, "Waiting")
        XCTAssertEqual(
            DictationRuntimeStatus.blocked(.readinessBlocked(.activeModelMissing(modelID: ProductionModelPolicy.requiredModelID))).menuStatusTitle,
            "Setup Required"
        )
        XCTAssertEqual(
            ReadinessBlocker.activeModelMissing(modelID: ProductionModelPolicy.requiredModelID).menuBlockerSummary,
            "Model not installed"
        )
    }

    func testOverlayIsVisibleOnlyWhileRecording() {
        XCTAssertEqual(
            DictationOverlayPresentation.state(for: .recording(speechDetected: false)),
            .recording(remainingSeconds: nil)
        )
        XCTAssertEqual(DictationOverlayPresentation.state(for: .processing), .hidden)
        XCTAssertEqual(DictationOverlayPresentation.state(for: .idle), .hidden)
    }

    func testLongDictationOverlayCopyWarnsOnlyDuringFinalTenSeconds() {
        XCTAssertEqual(
            DictationSessionPresentationCopy.remainingRecordingSeconds(
                deadlineUptimeMilliseconds: 300_000,
                nowUptimeMilliseconds: 0
            ),
            300
        )
        XCTAssertEqual(
            DictationSessionPresentationCopy.remainingRecordingSeconds(
                deadlineUptimeMilliseconds: 300_000,
                nowUptimeMilliseconds: 290_001
            ),
            10
        )
        XCTAssertEqual(
            DictationSessionPresentationCopy.remainingRecordingSeconds(
                deadlineUptimeMilliseconds: 300_000,
                nowUptimeMilliseconds: 299_001
            ),
            1
        )
        XCTAssertEqual(
            DictationSessionPresentationCopy.remainingRecordingSeconds(
                deadlineUptimeMilliseconds: 300_000,
                nowUptimeMilliseconds: 300_001
            ),
            0
        )
        XCTAssertNil(
            DictationSessionPresentationCopy.recordingWarning(
                remainingSeconds: 11
            )
        )
        XCTAssertEqual(
            DictationSessionPresentationCopy.recordingWarning(
                remainingSeconds: 10
            ),
            "Recording stops in 10s"
        )
        XCTAssertEqual(
            DictationSessionPresentationCopy.recordingWarning(
                remainingSeconds: 1
            ),
            "Recording stops in 1s"
        )
        XCTAssertNil(
            DictationSessionPresentationCopy.recordingWarning(
                remainingSeconds: 0
            )
        )
    }

    func testLongDictationOverlayCopyExplainsLimitAndWindowProgress() {
        XCTAssertEqual(
            DictationSessionPresentationCopy.sessionLimitReached,
            "5-minute limit reached — processing captured speech."
        )
        XCTAssertEqual(
            DictationSessionPresentationCopy.processingProgress(
                completedWindows: 2,
                totalWindows: 4
            ),
            "Processing 2 of 4"
        )
        XCTAssertNil(
            DictationSessionPresentationCopy.processingProgress(
                completedWindows: 1,
                totalWindows: 1
            )
        )
    }

    func testMenuCopyMatchesLongDictationOverlayCopy() {
        XCTAssertEqual(
            MenuBarPresentation.dictationStatusTitle(
                overlayState: .recording(remainingSeconds: 10),
                fallback: "Recording"
            ),
            "Recording stops in 10s"
        )
        XCTAssertEqual(
            MenuBarPresentation.dictationStatusTitle(
                overlayState: .sessionLimitReached,
                fallback: "Processing"
            ),
            "5-minute limit reached — processing captured speech."
        )
        XCTAssertEqual(
            MenuBarPresentation.dictationStatusTitle(
                overlayState: .processingProgress(
                    completedWindows: 2,
                    totalWindows: 4
                ),
                fallback: "Processing"
            ),
            "Processing 2 of 4"
        )
    }

    func testRecordingOverlayCapturesApplicationOncePerExplicitSession() {
        let firstSession = UUID()
        let secondSession = UUID()
        XCTAssertTrue(
            RecordingOverlayApplicationCapturePolicy.shouldCapture(
                currentSessionID: nil,
                nextSessionID: firstSession,
                hasSessionApplication: false
            )
        )
        XCTAssertFalse(
            RecordingOverlayApplicationCapturePolicy.shouldCapture(
                currentSessionID: firstSession,
                nextSessionID: firstSession,
                hasSessionApplication: true
            )
        )
        XCTAssertFalse(
            RecordingOverlayApplicationCapturePolicy.shouldCapture(
                currentSessionID: firstSession,
                nextSessionID: firstSession,
                hasSessionApplication: true
            )
        )
        XCTAssertTrue(
            RecordingOverlayApplicationCapturePolicy.shouldCapture(
                currentSessionID: firstSession,
                nextSessionID: secondSession,
                hasSessionApplication: true
            )
        )
    }

    func testRecordingOverlayGeometryAppliesOffsetsAndScale() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let preferences = RecordingOverlayPreferences(
            xOffset: 100,
            yOffset: 200,
            scale: 1.5
        )

        let frame = RecordingOverlayGeometry.frame(
            visibleFrame: visibleFrame,
            preferences: preferences
        )

        XCTAssertEqual(frame.width, 516)
        XCTAssertEqual(frame.height, 132)
        XCTAssertEqual(frame.origin.x, 562)
        XCTAssertEqual(frame.origin.y, 222)
    }

    func testRecordingOverlayGeometryKeepsWindowInsideVisibleScreen() {
        let visibleFrame = CGRect(x: 40, y: 30, width: 800, height: 600)
        let preferences = RecordingOverlayPreferences(
            xOffset: 800,
            yOffset: 800,
            scale: 2
        )

        let frame = RecordingOverlayGeometry.frame(
            visibleFrame: visibleFrame,
            preferences: preferences
        )

        XCTAssertEqual(frame.maxX, visibleFrame.maxX)
        XCTAssertEqual(frame.maxY, visibleFrame.maxY)
        XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY)
    }

    func testOnboardingFlowAndDonePreferenceMutation() {
        XCTAssertEqual(
            OnboardingStep.productionFlow,
            [.welcome, .model, .microphone, .accessibility, .triggerTest, .completion]
        )

        var preferences = AppPreferences.defaults
        preferences.launchAtLoginEnabled = false
        preferences.onboardingCompleted = false

        OnboardingCompletion.apply(to: &preferences, launchAtLogin: true)

        XCTAssertTrue(preferences.launchAtLoginEnabled)
        XCTAssertTrue(preferences.onboardingCompleted)
    }

    func testProductionModelConfigurationEmbedsTrustedKeys() {
        XCTAssertEqual(ProductionModelPresentation.visibleCatalog.map(\.id), [ProductionModelPolicy.requiredModelID])
        XCTAssertEqual(ProductionModelPresentation.v1_1.displayName, "Balanced - Whisper small.en q5_1")
        XCTAssertEqual(
            ProductionModelInstallConfiguration.current?.trustedKeys.first?.keyId,
            "textify-model-manifest-2026-primary"
        )
        XCTAssertEqual(ProductionModelInstallConfiguration.current?.trustedKeys.count, 3)
        XCTAssertFalse(ProductionModelInstallConfiguration.current?.trustedKeys.first?.publicKeyBase64.isEmpty ?? true)
        XCTAssertEqual(
            ProductionModelInstallConfiguration.current?.trustedKeys.last?.keyId,
            "textify-model-manifest-2026-huggingface"
        )
    }

    func testBundledSignedCatalogLoadsAsTheOnlyCatalogSource() throws {
        let temporaryResources = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyModelCatalog-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryResources) }
        let bundledDirectory = temporaryResources.appendingPathComponent(
            ProductionModelManifestLoader.bundledDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: bundledDirectory,
            withIntermediateDirectories: true
        )
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        try FileManager.default.copyItem(
            at: repositoryRoot.appendingPathComponent("models/manifest.json"),
            to: bundledDirectory.appendingPathComponent("manifest.json")
        )
        try FileManager.default.copyItem(
            at: repositoryRoot.appendingPathComponent("models/manifest.json.sig"),
            to: bundledDirectory.appendingPathComponent("manifest.json.sig")
        )
        let configuration = ProductionModelInstallConfiguration(
            trustedKeys: [
                TrustedModelManifestKey(
                    keyId: "textify-model-manifest-2026-huggingface",
                    publicKeyBase64: "eg6XVGVQ4Kqh1dtN3B8JcFTtK0RSxkxd79W5tfIlfos="
                ),
            ]
        )

        let snapshot = try XCTUnwrap(ProductionModelManifestLoader(
            configuration: configuration,
            resourceDirectory: temporaryResources
        ).loadBundledSnapshot())
        let manifest = snapshot.manifest

        XCTAssertEqual(manifest.manifestVersion, 3)
        XCTAssertNotNil(manifest.presentationGraph)
        XCTAssertEqual(
            manifest.models.map(\.id),
            [
                "ggml-small.en-q5_1",
                "whisper-large-v2-q5_0",
                "whisper-large-v3-q5_0",
                "whisper-large-v3-turbo-q5_0",
                "canary-qwen-2.5b-q4-k-m",
                "parakeet-tdt-0.6b-v3",
                "parakeet-tdt-ctc-110m",
                "parakeet-tdt-0.6b-v2",
                "parakeet-rnnt-1.1b",
                "cohere-transcribe-03-2026-mlx-8bit",
                "whisper-large-v3-turbo-mlx",
                "parakeet-ja",
                "paraformer-large-zh-int8",
                "reazonspeech-k2-v2-int8",
                "sensevoice-small-int8-2024-07-17",
                "qwen3-asr-0.6b-mlx-8bit",
                "qwen3-asr-1.7b-mlx-8bit",
                "qwen3-asr-0.6b-bf16",
                "qwen3-asr-0.6b-q8-0",
                "qwen3-asr-0.6b-q5-k-m",
                "qwen3-asr-1.7b-bf16",
                "qwen3-asr-1.7b-q8-0",
                "qwen3-asr-1.7b-q5-k-m",
                "parakeet-tdt-0.6b-v2-mlx",
                "parakeet-tdt-0.6b-v3-mlx",
                "nemotron-3.5-asr-streaming-0.6b-mlx",
                "parakeet-tdt-0.6b-v2-f16",
                "parakeet-tdt-0.6b-v2-q8-0",
                "parakeet-tdt-0.6b-v2-q5-k-m",
                "parakeet-tdt-0.6b-v3-f16",
                "parakeet-tdt-0.6b-v3-q8-0",
                "parakeet-tdt-0.6b-v3-q5-k-m",
                "nemotron-3.5-asr-streaming-0.6b-f16",
                "nemotron-3.5-asr-streaming-0.6b-q8-0",
                "nemotron-3.5-asr-streaming-0.6b-q5-k-m",
                "granite-speech-4.1-2b-q5-k-m",
                "granite-speech-4.1-2b-nar-q5-k-m",
                "voxtral-mini-4b-realtime-2602-q4-k-m",
                "moss-transcribe-diarize-0.9b-q5-k-m",
                "crisperwhisper-2-large-f16",
                "crisperwhisper-2-turbo-f16",
                "mossformer2-se-fp32",
                "mossformer2-se-fp16",
                "mossformer2-se-int8",
            ]
        )
    }

    func testModelInstallProgressPresentationShowsDownloadProgress() {
        let state = DownloadState(
            modelID: ProductionModelPolicy.requiredModelID,
            phase: .downloading,
            bytesDownloaded: 95_000_000,
            totalBytes: 190_000_000
        )

        XCTAssertEqual(ModelInstallProgressPresentation.title(for: state), "Downloading model")
        XCTAssertEqual(ModelInstallProgressPresentation.percentText(for: state), "50%")
        XCTAssertEqual(ModelInstallProgressPresentation.progressValue(for: state), 0.5)
    }

    func testModelInstallProgressIsScopedToItsCatalogRow() {
        let state = DownloadState(
            modelID: "parakeet-tdt-0.6b-v2",
            phase: .downloading,
            bytesDownloaded: 95_000_000,
            totalBytes: 190_000_000
        )

        XCTAssertEqual(
            ModelInstallRowPresentation.state(for: "parakeet-tdt-0.6b-v2", from: state),
            state
        )
        XCTAssertNil(ModelInstallRowPresentation.state(for: "whisper-large-v3-turbo-mlx", from: state))
        XCTAssertTrue(ModelInstallRowPresentation.offersCancel(for: state))
        XCTAssertFalse(ModelInstallRowPresentation.offersRetry(for: state))

        let failed = DownloadState(modelID: state.modelID, phase: .failed)
        XCTAssertFalse(ModelInstallRowPresentation.offersCancel(for: failed))
        XCTAssertTrue(ModelInstallRowPresentation.offersRetry(for: failed))

        let installed = DownloadState(modelID: state.modelID, phase: .installed)
        XCTAssertNil(ModelInstallRowPresentation.state(for: state.modelID, from: installed))
    }

    func testDownloadsPresentationClassifiesEveryQueueStatusAndExactControl() {
        let phases: [DownloadPhase] = [
            .downloading,
            .queued,
            .paused,
            .waitingForNetwork,
            .waitingForCatalogCheck,
            .installed,
            .failed,
            .cancelled,
            .revoked,
        ]
        let attempts = phases.enumerated().map { index, phase in
            ModelInstallQueueAttempt(
                id: "attempt-\(index)",
                artifactID: "artifact-\(index)",
                purpose: index.isMultiple(of: 2)
                    ? .transcription
                    : .voiceCleaning,
                action: index == 0 ? .install : .reinstall,
                createdAt: "2026-07-24T10:0\(index):00Z",
                state: DownloadState(
                    modelID: "artifact-\(index)",
                    phase: phase,
                    bytesDownloaded: phase == .downloading ? 25 : 0,
                    totalBytes: phase == .downloading ? 100 : 0
                ),
                resumableData: phase == .revoked
                    ? ModelInstallResumableData(
                        sourceAttemptID: "attempt-\(index)",
                        associatedAttemptID: "attempt-\(index)",
                        validatedBytes: 1_024,
                        fileCount: 1
                    )
                    : nil
            )
        }

        let presentation = ModelDownloadsPresentation(attempts: attempts)

        XCTAssertEqual(presentation.active.map(\.id), ["attempt-0"])
        XCTAssertEqual(
            presentation.pending.map(\.id),
            ["attempt-1", "attempt-2", "attempt-3", "attempt-4"]
        )
        XCTAssertEqual(
            presentation.history.map(\.id),
            ["attempt-5", "attempt-6", "attempt-7", "attempt-8"]
        )
        XCTAssertEqual(presentation.nonterminalCount, 5)
        XCTAssertTrue(presentation.active[0].canPause)
        XCTAssertTrue(presentation.pending[0].canCancel)
        XCTAssertTrue(presentation.pending[1].canResume)
        XCTAssertFalse(presentation.pending[2].canResume)
        XCTAssertTrue(presentation.pending[3].canRetry)
        XCTAssertTrue(presentation.pending[3].canCancel)
        XCTAssertTrue(presentation.history[1].canRetry)
        XCTAssertFalse(presentation.history[3].canRetry)
        XCTAssertTrue(
            presentation.history[3].canRemoveRetainedData
        )
        XCTAssertTrue(
            presentation.history[3].detailText.contains(
                "not resumable"
            )
        )
        XCTAssertEqual(
            presentation.pending[2].revealRequest,
            ModelCatalogRevealRequest(
                artifactID: "artifact-3",
                purpose: .voiceCleaning
            )
        )
        XCTAssertEqual(presentation.history[0].statusTitle, "Model installed")
        XCTAssertEqual(presentation.history[3].statusTitle, "Install revoked")
    }

    func testDownloadsHidesRetainedRemovalWhileSameArtifactAttemptIsActive() {
        let retained = ModelInstallQueueAttempt(
            id: "attempt-1",
            artifactID: "artifact-a",
            purpose: .transcription,
            action: .install,
            createdAt: "2026-07-24T10:00:00Z",
            state: DownloadState(
                modelID: "artifact-a",
                phase: .revoked
            ),
            resumableData: ModelInstallResumableData(
                sourceAttemptID: "attempt-1",
                associatedAttemptID: "attempt-1",
                validatedBytes: 1_024,
                fileCount: 1
            )
        )
        let active = ModelInstallQueueAttempt(
            id: "attempt-2",
            artifactID: "artifact-a",
            purpose: .transcription,
            action: .reinstall,
            createdAt: "2026-07-24T10:01:00Z",
            state: DownloadState(
                modelID: "artifact-a",
                phase: .downloading
            )
        )

        let activePresentation = ModelDownloadsPresentation(
            attempts: [retained, active]
        )
        let idlePresentation = ModelDownloadsPresentation(
            attempts: [retained]
        )

        XCTAssertFalse(
            activePresentation.history[0].canRemoveRetainedData
        )
        XCTAssertTrue(
            idlePresentation.history[0].canRemoveRetainedData
        )
    }

    func testLaunchAtLoginToggleUsesLiveStatus() {
        XCTAssertTrue(LaunchAtLoginToggleModel.isOn(status: .enabled))
        XCTAssertFalse(LaunchAtLoginToggleModel.isOn(status: .disabled))
        XCTAssertFalse(LaunchAtLoginToggleModel.isOn(status: .requiresApproval))
        XCTAssertFalse(LaunchAtLoginToggleModel.isOn(status: .unsupportedLocation))
        XCTAssertFalse(LaunchAtLoginToggleModel.isOn(status: .failed("fixture")))
    }

    func testOnboardingLaunchAtLoginNoticeKeepsActionVisibleForApproval() {
        XCTAssertEqual(
            OnboardingLaunchAtLoginNotice.message(for: .requiresApproval),
            "macOS needs approval before Textify can open at login."
        )
        XCTAssertTrue(OnboardingLaunchAtLoginNotice.showsLoginItemsAction(for: .requiresApproval))
        XCTAssertNil(OnboardingLaunchAtLoginNotice.message(for: .enabled))
        XCTAssertFalse(OnboardingLaunchAtLoginNotice.showsLoginItemsAction(for: .enabled))
    }

    private func benchmarkRating(
        modelID: String,
        qualityScore: Int,
        qualityLevel: Int,
        speedScore: Int,
        speedLevel: Int
    ) -> ModelBenchmarkRating {
        ModelBenchmarkRating(
            schemaVersion: 1,
            policyID: "english-catalog-rating-v2",
            suiteID: "english-catalog-rating-v1",
            suiteIndexSHA256: String(repeating: "a", count: 64),
            modelID: modelID,
            engine: "test-engine",
            engineVersion: "test-engine-1",
            modelLicense: "MIT",
            computeBackend: "Metal",
            artifactFingerprint: String(repeating: "b", count: 64),
            sourceRevision: String(repeating: "c", count: 40),
            language: "en",
            measuredAt: "2026-07-22T00:00:00Z",
            referenceHost: ModelBenchmarkHost(
                chip: "Apple M4 Max",
                operatingSystem: "macOS 26.5.2 (25F84)",
                architecture: "arm64"
            ),
            runCount: 3,
            quality: ModelBenchmarkQualityRating(
                score: qualityScore,
                level: qualityLevel,
                label: qualityLevel == 5 ? "Highest" : qualityLevel == 4 ? "High" : "Balanced",
                speechItems: 732,
                noSpeechItems: 200,
                noSpeechFalsePositiveRate: 0,
                components: [
                    ModelBenchmarkQualityComponent(
                        id: "open-asr-english-nightly-v1",
                        wordErrorRate: 0.1,
                        score: Double(qualityScore),
                        weight: 0.5
                    ),
                    ModelBenchmarkQualityComponent(
                        id: "edacc-english-nightly-v1",
                        wordErrorRate: 0.2,
                        score: Double(qualityScore),
                        weight: 0.3
                    ),
                    ModelBenchmarkQualityComponent(
                        id: "berst-english-nightly-v1",
                        wordErrorRate: 0.3,
                        score: Double(qualityScore),
                        weight: 0.2
                    ),
                ]
            ),
            speed: ModelBenchmarkSpeedRating(
                score: speedScore,
                level: speedLevel,
                label: speedLevel == 5 ? "Fastest" : speedLevel == 4 ? "Fast" : "Balanced",
                p50ReleaseToFinalMs: 180,
                p95ReleaseToFinalMs: 205,
                p95RealTimeFactor: 0.05,
                relativeP95Spread: 0.05
            ),
            speedUnratedReason: nil
        )
    }
}
