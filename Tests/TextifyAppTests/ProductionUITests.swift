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

    func testOnboardingFlowAndDonePreferenceMutation() {
        XCTAssertEqual(
            OnboardingStep.productionFlow,
            [.welcome, .model, .microphone, .accessibility, .inputMonitoring, .triggerTest, .completion]
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
        XCTAssertEqual(ProductionModelInstallConfiguration.current?.trustedKeys.count, 2)
        XCTAssertFalse(ProductionModelInstallConfiguration.current?.trustedKeys.first?.publicKeyBase64.isEmpty ?? true)
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
