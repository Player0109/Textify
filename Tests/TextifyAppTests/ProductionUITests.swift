import XCTest
@testable import Textify
import TextifyModels
import TextifyRuntime
import TextifySettings

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
            [.general, .dictation, .models, .privacy, .advanced]
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
            iconData: nil,
            path: "/Applications/Editor.app"
        )

        let once = ExcludedAppsSettingsModel.adding(candidate, to: [])
        let twice = ExcludedAppsSettingsModel.adding(candidate, to: once)

        XCTAssertEqual(once.count, 1)
        XCTAssertEqual(twice, once)
        XCTAssertEqual(once.first?.bundleIdentifier, "com.example.Editor")
        XCTAssertEqual(once.first?.lastKnownPath, "/Applications/Editor.app")
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
            .recording(elapsedSeconds: 0)
        )
        XCTAssertEqual(DictationOverlayPresentation.state(for: .processing), .hidden)
        XCTAssertEqual(DictationOverlayPresentation.state(for: .idle), .hidden)
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

    func testProductionModelPresentationShowsOnlyRequiredModel() {
        XCTAssertEqual(ProductionModelPresentation.visibleCatalog.map(\.id), [ProductionModelPolicy.requiredModelID])
        XCTAssertEqual(ProductionModelPresentation.v1_1.displayName, "Balanced - Whisper small.en q5_1")
        XCTAssertEqual(
            ProductionModelInstallConfiguration.current?.manifestURL.absoluteString,
            "https://player0109.github.io/Textify/models/manifest.json"
        )
        XCTAssertEqual(
            ProductionModelInstallConfiguration.current?.signatureURL.absoluteString,
            "https://player0109.github.io/Textify/models/manifest.json.sig"
        )
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

    func testBundledModelCatalogWinsWhenRemoteCatalogIsOlder() throws {
        let bundled = ModelManifest(
            manifestVersion: 1,
            generatedAt: "2026-07-19T09:43:39Z",
            models: []
        )
        let remote = ModelManifest(
            manifestVersion: 1,
            generatedAt: "2026-07-03T00:00:00Z",
            models: []
        )

        XCTAssertEqual(
            try ProductionModelManifestLoader.newest(bundled: bundled, remote: remote),
            bundled
        )
    }

    func testRemoteModelCatalogWinsWhenItIsAtLeastAsNewAsBundledCatalog() throws {
        let bundled = ModelManifest(
            manifestVersion: 1,
            generatedAt: "2026-07-19T09:43:39Z",
            models: []
        )
        let remote = ModelManifest(
            manifestVersion: 1,
            generatedAt: "2026-07-20T00:00:00Z",
            models: []
        )

        XCTAssertEqual(
            try ProductionModelManifestLoader.newest(bundled: bundled, remote: remote),
            remote
        )
    }

    func testBundledSignedCatalogLoadsWhenRemoteCatalogIsUnavailable() async throws {
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
            manifestURL: URL(string: "http://invalid.example/manifest.json")!,
            signatureURL: URL(string: "http://invalid.example/manifest.json.sig")!,
            trustedKeys: [
                TrustedModelManifestKey(
                    keyId: "textify-model-manifest-2026-huggingface",
                    publicKeyBase64: "eg6XVGVQ4Kqh1dtN3B8JcFTtK0RSxkxd79W5tfIlfos="
                )
            ]
        )

        let manifest = try await ProductionModelManifestLoader(
            configuration: configuration,
            resourceDirectory: temporaryResources
        ).load()

        XCTAssertEqual(
            manifest.models.map(\.id),
            [
                "ggml-small.en-q5_1",
                "whisper-large-v3-turbo-q5_0",
                "parakeet-tdt-0.6b-v3",
                "parakeet-tdt-ctc-110m",
                "parakeet-tdt-0.6b-v2",
                "parakeet-ja",
                "paraformer-large-zh-int8",
                "reazonspeech-k2-v2-int8",
                "sensevoice-small-int8-2024-07-17",
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
}
