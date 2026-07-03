public enum TriggerPreference: String, Codable, CaseIterable, Equatable, Sendable {
    case rightCommand
    case rightOption
    case rightControl
    case controlSpace
}

public enum TranscriptionLanguage: String, Codable, CaseIterable, Equatable, Sendable {
    case english = "en"
}

public enum ModelSelectionScope: String, Codable, Equatable, Sendable {
    case curatedInstalledModels
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public static let supportedTranscriptionLanguages: [TranscriptionLanguage] = [.english]
    public static let allowsArbitraryModelImports = false
    public static let supportsPerAppProfiles = false

    public var trigger: TriggerPreference
    public var microphoneSelection: MicrophoneSelection
    public var transcriptionLanguage: TranscriptionLanguage
    public var modelSelectionScope: ModelSelectionScope
    public var activeModelID: String?
    public var showInDock: Bool
    public var automaticallyCheckForUpdates: Bool
    public var launchAtLoginEnabled: Bool
    public var onboardingCompleted: Bool
    public var excludedApps: [ExcludedApp]
    public var hasShownNoModelNotice: Bool
    public var hasShownMicRevokedNotice: Bool
    public var hasShownAccessibilityRevokedNotice: Bool
    public var hasShownInputMonitoringRevokedNotice: Bool

    public var launchAtLoginRequestedByOnboarding: Bool {
        get { launchAtLoginEnabled }
        set { launchAtLoginEnabled = newValue }
    }

    public init(
        trigger: TriggerPreference = .rightCommand,
        microphoneSelection: MicrophoneSelection = .systemDefault,
        transcriptionLanguage: TranscriptionLanguage = .english,
        modelSelectionScope: ModelSelectionScope = .curatedInstalledModels,
        activeModelID: String? = nil,
        showInDock: Bool = false,
        automaticallyCheckForUpdates: Bool = true,
        launchAtLoginEnabled: Bool = true,
        onboardingCompleted: Bool = false,
        excludedApps: [ExcludedApp] = [],
        hasShownNoModelNotice: Bool = false,
        hasShownMicRevokedNotice: Bool = false,
        hasShownAccessibilityRevokedNotice: Bool = false,
        hasShownInputMonitoringRevokedNotice: Bool = false
    ) {
        self.trigger = trigger
        self.microphoneSelection = microphoneSelection
        self.transcriptionLanguage = transcriptionLanguage
        self.modelSelectionScope = modelSelectionScope
        self.activeModelID = activeModelID
        self.showInDock = showInDock
        self.automaticallyCheckForUpdates = automaticallyCheckForUpdates
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.onboardingCompleted = onboardingCompleted
        self.excludedApps = excludedApps
        self.hasShownNoModelNotice = hasShownNoModelNotice
        self.hasShownMicRevokedNotice = hasShownMicRevokedNotice
        self.hasShownAccessibilityRevokedNotice = hasShownAccessibilityRevokedNotice
        self.hasShownInputMonitoringRevokedNotice = hasShownInputMonitoringRevokedNotice
    }

    public static var defaults: AppPreferences {
        AppPreferences()
    }

    public mutating func resetOnboardingState() {
        onboardingCompleted = false
        clearOneTimeNoticeFlags()
    }

    public mutating func clearOneTimeNoticeFlags() {
        hasShownNoModelNotice = false
        hasShownMicRevokedNotice = false
        hasShownAccessibilityRevokedNotice = false
        hasShownInputMonitoringRevokedNotice = false
    }

    private enum CodingKeys: String, CodingKey {
        case trigger
        case microphoneSelection
        case transcriptionLanguage
        case modelSelectionScope
        case activeModelID
        case showInDock
        case automaticallyCheckForUpdates
        case launchAtLoginEnabled
        case launchAtLoginRequestedByOnboarding
        case onboardingCompleted
        case excludedApps
        case hasShownNoModelNotice
        case hasShownMicRevokedNotice
        case hasShownAccessibilityRevokedNotice
        case hasShownInputMonitoringRevokedNotice
    }

    public init(from decoder: Decoder) throws {
        let defaults = AppPreferences.defaults
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLoginEnabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .launchAtLoginRequestedByOnboarding)
            ?? defaults.launchAtLoginEnabled

        self.init(
            trigger: try container.decodeIfPresent(TriggerPreference.self, forKey: .trigger) ?? defaults.trigger,
            microphoneSelection: try container.decodeIfPresent(MicrophoneSelection.self, forKey: .microphoneSelection) ?? defaults.microphoneSelection,
            transcriptionLanguage: try container.decodeIfPresent(TranscriptionLanguage.self, forKey: .transcriptionLanguage) ?? defaults.transcriptionLanguage,
            modelSelectionScope: try container.decodeIfPresent(ModelSelectionScope.self, forKey: .modelSelectionScope) ?? defaults.modelSelectionScope,
            activeModelID: try container.decodeIfPresent(String.self, forKey: .activeModelID) ?? defaults.activeModelID,
            showInDock: try container.decodeIfPresent(Bool.self, forKey: .showInDock) ?? defaults.showInDock,
            automaticallyCheckForUpdates: try container.decodeIfPresent(Bool.self, forKey: .automaticallyCheckForUpdates) ?? defaults.automaticallyCheckForUpdates,
            launchAtLoginEnabled: launchAtLogin,
            onboardingCompleted: try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? defaults.onboardingCompleted,
            excludedApps: try container.decodeIfPresent([ExcludedApp].self, forKey: .excludedApps) ?? defaults.excludedApps,
            hasShownNoModelNotice: try container.decodeIfPresent(Bool.self, forKey: .hasShownNoModelNotice) ?? defaults.hasShownNoModelNotice,
            hasShownMicRevokedNotice: try container.decodeIfPresent(Bool.self, forKey: .hasShownMicRevokedNotice) ?? defaults.hasShownMicRevokedNotice,
            hasShownAccessibilityRevokedNotice: try container.decodeIfPresent(Bool.self, forKey: .hasShownAccessibilityRevokedNotice) ?? defaults.hasShownAccessibilityRevokedNotice,
            hasShownInputMonitoringRevokedNotice: try container.decodeIfPresent(Bool.self, forKey: .hasShownInputMonitoringRevokedNotice) ?? defaults.hasShownInputMonitoringRevokedNotice
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(trigger, forKey: .trigger)
        try container.encode(microphoneSelection, forKey: .microphoneSelection)
        try container.encode(transcriptionLanguage, forKey: .transcriptionLanguage)
        try container.encode(modelSelectionScope, forKey: .modelSelectionScope)
        try container.encodeIfPresent(activeModelID, forKey: .activeModelID)
        try container.encode(showInDock, forKey: .showInDock)
        try container.encode(automaticallyCheckForUpdates, forKey: .automaticallyCheckForUpdates)
        try container.encode(launchAtLoginEnabled, forKey: .launchAtLoginEnabled)
        try container.encode(onboardingCompleted, forKey: .onboardingCompleted)
        try container.encode(excludedApps, forKey: .excludedApps)
        try container.encode(hasShownNoModelNotice, forKey: .hasShownNoModelNotice)
        try container.encode(hasShownMicRevokedNotice, forKey: .hasShownMicRevokedNotice)
        try container.encode(hasShownAccessibilityRevokedNotice, forKey: .hasShownAccessibilityRevokedNotice)
        try container.encode(hasShownInputMonitoringRevokedNotice, forKey: .hasShownInputMonitoringRevokedNotice)
    }
}
