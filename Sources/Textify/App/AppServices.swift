import Foundation
import Observation
import TextifyCore
import TextifyDiagnostics
import TextifyInsertion
import TextifyModels
import TextifySettings
import TextifyTranscription

@MainActor
@Observable
final class AppServices {
    let settingsRouter = SettingsRouter()
    let settingsStore: SettingsStore
    let diagnosticsLogger: DiagnosticsLogger
    let fakeInsertionService: DevelopmentInsertionService

    var preferences: AppPreferences
    var modelCatalog: ModelCatalogState
    var mockTranscriptionProvider: MockTranscriptionProvider
    var dictationController: DictationController
    var updateStatus = MockActionStatus.idle
    var mockDictationStatus = MockActionStatus.idle
    var onboardingStep = OnboardingStep.welcome
    var overlayState = RecordingOverlayState.hidden

    init(
        settingsStore: SettingsStore = SettingsStore(storage: .memory),
        diagnosticsLogger: DiagnosticsLogger = DiagnosticsLogger(directory: AppServices.defaultDiagnosticsDirectory),
        fakeInsertionService: DevelopmentInsertionService = DevelopmentInsertionService()
    ) {
        self.settingsStore = settingsStore
        self.diagnosticsLogger = diagnosticsLogger
        self.fakeInsertionService = fakeInsertionService
        self.preferences = settingsStore.load()
        self.modelCatalog = .v1Preview
        self.mockTranscriptionProvider = Self.makeMockTranscriptionProvider()
        self.dictationController = Self.makeMockDictationController(transcript: Self.developmentMockTranscript)
    }

    var canRunMockDictation: Bool {
        mockDictationStatus != .running
    }

    func runMockDictation() async {
        guard canRunMockDictation else {
            return
        }

        mockDictationStatus = .running
        overlayState = .recording(elapsedSeconds: 0)

        do {
            mockTranscriptionProvider = Self.makeMockTranscriptionProvider()
            let result = try await mockTranscriptionProvider.transcribe(.emptyForTests)
            dictationController = Self.makeMockDictationController(transcript: result.text)
            await dictationController.runDevelopmentMockCycle()

            let outcome = await fakeInsertionService.insert(InsertionRequest(text: result.text))
            try await logMockInsertion(text: result.text, outcome: outcome)

            overlayState = .hidden
            mockDictationStatus = .succeeded("Mock dictation inserted")
        } catch {
            overlayState = .blocked("Mock dictation failed")
            mockDictationStatus = .unavailable("Mock dictation failed")
        }
    }

    func savePreferences() {
        settingsStore.save(preferences)
    }

    private func logMockInsertion(text: String, outcome: InsertionOutcome) async throws {
        let pasteSucceeded: Bool
        if case .pasted = outcome {
            pasteSucceeded = true
        } else {
            pasteSucceeded = false
        }

        try await diagnosticsLogger.log(
            .insertionAttempt(
                textLengthBucket: Self.textLengthBucket(for: text.count),
                pasteboardSnapshotSucceeded: true,
                pasteboardWriteSucceeded: pasteSucceeded,
                pasteEventPosted: pasteSucceeded,
                fallbackAttempted: false,
                fallbackBlockedReason: nil,
                durationMs: 0
            )
        )
    }

    private nonisolated static func makeMockTranscriptionProvider() -> MockTranscriptionProvider {
        MockTranscriptionProvider(
            results: [
                TranscriptionResult(
                    text: developmentMockTranscript,
                    noSpeechProbability: 0.01,
                    averageLogProbability: -0.1,
                    compressionRatio: 1.1
                )
            ]
        )
    }

    private nonisolated static func makeMockDictationController(transcript: String) -> DictationController {
        DictationController(
            fakeAudio: FakeDictationAudio(),
            fakeTranscriber: FakeDictationTranscriber(transcripts: [transcript]),
            fakeInsertion: FakeDictationInsertion()
        )
    }

    private nonisolated static func textLengthBucket(for count: Int) -> String {
        switch count {
        case 0:
            return "0"
        case 1...50:
            return "1-50"
        case 51...200:
            return "51-200"
        case 201...500:
            return "201-500"
        default:
            return "501+"
        }
    }

    private nonisolated static let developmentMockTranscript = "Textify mock dictation."

    private nonisolated static var defaultDiagnosticsDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyDevelopmentDiagnostics", isDirectory: true)
    }
}

@Observable
final class SettingsRouter {
    var selectedPane: SettingsPane = .general
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case dictation
    case models
    case vocabulary
    case privacy
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .dictation:
            return "Dictation"
        case .models:
            return "Models"
        case .vocabulary:
            return "Vocabulary"
        case .privacy:
            return "Privacy"
        case .advanced:
            return "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .dictation:
            return "mic"
        case .models:
            return "externaldrive"
        case .vocabulary:
            return "textformat.abc"
        case .privacy:
            return "hand.raised"
        case .advanced:
            return "slider.horizontal.3"
        }
    }
}

enum MockActionStatus: Equatable {
    case idle
    case running
    case succeeded(String)
    case unavailable(String)

    var menuTitle: String? {
        switch self {
        case .idle:
            return nil
        case .running:
            return "Mock dictation running"
        case let .succeeded(message), let .unavailable(message):
            return message
        }
    }
}

struct ModelCatalogState: Equatable {
    var installedModels: InstalledModelsStore
    var curatedModels: [ModelCatalogItem]
    var activeModelID: String?

    static let v1Preview = ModelCatalogState(
        installedModels: InstalledModelsStore(),
        curatedModels: [
            ModelCatalogItem(id: "whisper-base-en-fast", tier: "Fast", name: "Whisper base.en", size: "TBD"),
            ModelCatalogItem(id: "whisper-small-en-balanced", tier: "Balanced", name: "Whisper small.en", size: "TBD"),
            ModelCatalogItem(id: "whisper-medium-en-accurate", tier: "Accurate", name: "Whisper medium.en", size: "TBD")
        ],
        activeModelID: nil
    )
}

struct ModelCatalogItem: Equatable, Identifiable {
    let id: String
    let tier: String
    let name: String
    let size: String
}

actor DevelopmentInsertionService: InsertionService {
    private(set) var insertedLengthBuckets: [String] = []

    func insert(_ request: InsertionRequest) async -> InsertionOutcome {
        insertedLengthBuckets.append(Self.textLengthBucket(for: request.text.count))
        return .pasted(PasteInsertionReport(pasteboardRestored: false, pasteboardRestoreFailed: false))
    }

    private static func textLengthBucket(for count: Int) -> String {
        switch count {
        case 0:
            return "0"
        case 1...50:
            return "1-50"
        case 51...200:
            return "51-200"
        case 201...500:
            return "201-500"
        default:
            return "501+"
        }
    }
}

enum OnboardingStep: String, CaseIterable, Identifiable {
    case welcome
    case model
    case microphone
    case accessibility
    case inputMonitoring
    case triggerTest
    case completion

    var id: Self { self }

    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .model:
            return "Model"
        case .microphone:
            return "Microphone"
        case .accessibility:
            return "Accessibility"
        case .inputMonitoring:
            return "Input Monitoring"
        case .triggerTest:
            return "Trigger Test"
        case .completion:
            return "Completion"
        }
    }
}

enum RecordingOverlayState: Equatable {
    case hidden
    case recording(elapsedSeconds: Int)
    case processing
    case cancelled
    case blocked(String)
}
