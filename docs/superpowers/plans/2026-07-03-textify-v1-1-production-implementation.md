# Textify V1.1 Production Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take Textify from the current mock-integrated scaffold to a production-ready V1.1 macOS menu bar dictation app that ships as an arm64 Developer ID signed, notarized, stapled GitHub Release DMG.

**Architecture:** Add a `TextifyRuntime` target as the production orchestration layer above the existing domain targets. Domain targets own concrete macOS or native primitives and never import `TextifyRuntime`; `TextifyRuntime` imports domain targets, adapts them behind runtime protocols, and owns readiness plus dictation session lifecycle. The `Textify` executable target owns SwiftUI/AppKit composition, onboarding, settings, menu bar lifecycle, and release-only UI cleanup.

**Tech Stack:** Swift 5.9, SwiftPM, XCTest, SwiftUI Observation, AppKit, AVFoundation, ApplicationServices, ServiceManagement, CryptoKit Ed25519, whisper.cpp via `TextifyWhisperShim`, Xcode archive/export, Developer ID signing, notarytool, hdiutil.

---

## Source Context

Every agent must read these files before editing:

- `AGENTS.md`
- `docs/SPEC.md`
- `docs/implementation/coordination.md`
- `docs/superpowers/plans/2026-07-03-textify-v1-parallel-implementation.md`
- This plan file

Current state at plan time:

- `Textify` builds and tests as a mock-integrated scaffold.
- Native whisper.cpp vendor/shim exists.
- Xcode project and bundle scaffold exist.
- Mock dictation is exposed in debug UI.
- Real AVAudioEngine capture, real CGEventTap hotkey monitoring, real paste insertion, production orchestration, production onboarding, and release scripts are not complete.

V1.1 production decisions already resolved:

- Default trigger: Right Command.
- No pre-roll; hold Right Command for 250 ms before recording starts.
- V1.1 model manifest has one production model entry: `ggml-small.en-q5_1`, display name `Balanced - Whisper small.en q5_1`, unless performance QA forces a faster English curated model before release.
- No bundled model.
- Manifest signature is detached `manifest.json.sig`, Ed25519 over exact raw `manifest.json` bytes.
- Sparkle is absent from V1.1 and deferred to V1.2.
- No transcript history, no audio history, no clipboard history, no visible history concept.
- Diagnostics are manual, redacted, and never include transcript text, inserted text, audio, clipboard data, frontmost app names, bundle IDs, or pasteboard marker UUIDs.
- Normal dictation audio, transcript text, and pasteboard snapshots are memory-only.

## Parallelization Map

| Wave | Tasks | Parallelism | Merge Gate |
| --- | --- | --- | --- |
| 0 | Task 0 | Serial | Runtime target compiles, all tests pass, no domain target imports `TextifyRuntime` |
| 1 | Tasks 1, 2, 3, 4, 5, 6 | Parallel after Wave 0 | Each domain target passes focused tests and full `swift test` |
| 2 | Tasks 7, 8 | Serial after Wave 1 public APIs land | Runtime adapters and orchestration pass fake-driven tests |
| 3 | Tasks 9, 10 | Task 9 first, Task 10 after or alongside small UI slices | App builds, Release UI has no mock dictation or Sparkle controls |
| 4 | Tasks 11, 12, 13 | Parallel after Wave 3 compiles | Release scripts validate without credentials where possible, public docs align with V1.1 |
| 5 | Task 14 | Serial | End-to-end production path and release candidate gates pass |

## Ownership Rules

- `TextifyRuntime` may import all domain targets.
- Domain targets must not import `TextifyRuntime`.
- `Textify` app target may import `TextifyRuntime` and any domain target needed for SwiftUI view labels, but it must not own production dictation orchestration.
- `AppServices` becomes composition and UI lifecycle glue only.
- If a task needs to change files outside its ownership list, update `docs/implementation/coordination.md` with the reason before editing.
- Each task ends with `swift test`.
- Use exact `git add` paths from each task. Do not use `git add .`.

## Shared Type Contracts

Task 0 introduces these contracts. Later tasks must use the same names unless they update all dependent tasks in one integration change.

```swift
public struct ReadinessSnapshot: Equatable, Sendable {
    public let permissions: RuntimePermissionSnapshot
    public let model: RuntimeModelReadiness
    public let blockers: [ReadinessBlocker]
    public var canDictate: Bool { blockers.isEmpty }
}

public struct RuntimePermissionSnapshot: Equatable, Sendable {
    public let microphone: RuntimePermissionState
    public let accessibility: RuntimePermissionState
    public let inputMonitoring: RuntimePermissionState
}

public enum RuntimePermissionState: Equatable, Sendable {
    case unknown
    case granted
    case denied
}

public enum RuntimeModelReadiness: Equatable, Sendable {
    case noActiveModel
    case missing(modelID: String)
    case loading(modelID: String)
    case warming(modelID: String)
    case ready(modelID: String)
    case failed(modelID: String, reason: RuntimeModelFailure)
}

public enum RuntimeModelFailure: Equatable, Sendable {
    case missingFile
    case checksumFailed
    case loadFailed
    case warmupFailed
}

public enum ReadinessBlocker: Equatable, Sendable {
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    case inputMonitoringPermissionDenied
    case noActiveModel
    case activeModelMissing(modelID: String)
    case activeModelNotReady(modelID: String)
    case transcriptionRuntimeFailed(modelID: String)
}
```

```swift
public enum DictationRuntimeStatus: Equatable, Sendable {
    case idle
    case waitingForActivation
    case recording(speechDetected: Bool)
    case processing
    case inserting
    case completed(textLengthBucket: String)
    case cancelled(DictationCancellationReason)
    case blocked(ProductionDictationError)
    case failed(ProductionDictationError)
}

public enum DictationCancellationReason: Equatable, Sendable {
    case releasedBeforeActivation
    case shortcutUseBeforeSpeech
    case escapeKey
    case noSpeechDetected
}

public enum ProductionDictationError: Error, Equatable, Sendable {
    case readinessBlocked(ReadinessBlocker)
    case concurrentDictation
    case audioStartFailed
    case audioFinishFailed
    case audioConversionFailed
    case microphoneChanged
    case transcriptionNotReady
    case transcriptionFailed
    case insertionFailed
}
```

```swift
public struct RuntimeActiveModel: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let tier: String
    public let localModelPath: String
    public let useGPU: Bool
    public let threadCount: Int?
}

public protocol RuntimeSettingsProviding: Sendable {
    func loadPreferences() async -> AppPreferences
    func savePreferences(_ preferences: AppPreferences) async
}

public protocol RuntimePermissionChecking: Sendable {
    func permissionSnapshot() async -> RuntimePermissionSnapshot
}

public protocol RuntimeModelResolving: Sendable {
    func resolveActiveModel(preferences: AppPreferences) async -> RuntimeActiveModel?
    func readiness(for model: RuntimeActiveModel?) async -> RuntimeModelReadiness
}

public protocol RuntimeAudioRecording: Sendable {
    func startRecording(
        microphone: MicrophoneSelection,
        onSpeechDetected: @escaping @Sendable () -> Void
    ) async throws
    func finishRecording() async throws -> CanonicalAudioBuffer
    func discardRecording() async
}

public protocol RuntimeTranscribing: Sendable {
    var readiness: RuntimeModelReadiness { get async }
    func prepare(model: RuntimeActiveModel) async throws
    func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult
}

public protocol RuntimeDiagnosticsLogging: Sendable {
    func log(_ event: DiagnosticEvent) async
}

public protocol RuntimePostProcessing: Sendable {
    func process(rawText: String, preferences: AppPreferences) async -> String
}

public protocol RuntimeClock: Sendable {
    func nowMilliseconds() -> Int
    func sleep(milliseconds: Int) async
}
```

## Task 0: TextifyRuntime Target And Contracts

**Files:**

- Modify: `Package.swift`
- Create: `Sources/TextifyRuntime/TextifyRuntime.swift`
- Create: `Sources/TextifyRuntime/Readiness/ReadinessSnapshot.swift`
- Create: `Sources/TextifyRuntime/Dictation/DictationRuntimeStatus.swift`
- Create: `Sources/TextifyRuntime/Dictation/ProductionDictationError.swift`
- Create: `Sources/TextifyRuntime/Dictation/AppDictationService.swift`
- Create: `Sources/TextifyRuntime/Protocols/RuntimeDependencies.swift`
- Create: `Tests/TextifyRuntimeTests/SmokeTests.swift`
- Create: `Tests/TextifyRuntimeTests/ReadinessSnapshotTests.swift`
- Modify: `docs/implementation/coordination.md`

- [ ] **Step 1: Write failing package smoke tests**

Create `Tests/TextifyRuntimeTests/SmokeTests.swift`:

```swift
import TextifyRuntime
import XCTest

final class TextifyRuntimeSmokeTests: XCTestCase {
    func testModuleMarker() {
        XCTAssertEqual(TextifyRuntimeModule.name, "TextifyRuntime")
    }
}
```

Create `Tests/TextifyRuntimeTests/ReadinessSnapshotTests.swift`:

```swift
import TextifyRuntime
import XCTest

final class ReadinessSnapshotTests: XCTestCase {
    func testCanDictateWhenThereAreNoBlockers() {
        let snapshot = ReadinessSnapshot(
            permissions: RuntimePermissionSnapshot(
                microphone: .granted,
                accessibility: .granted,
                inputMonitoring: .granted
            ),
            model: .ready(modelID: "ggml-small.en-q5_1"),
            blockers: []
        )

        XCTAssertTrue(snapshot.canDictate)
    }

    func testCannotDictateWhenThereAreBlockers() {
        let snapshot = ReadinessSnapshot(
            permissions: RuntimePermissionSnapshot(
                microphone: .denied,
                accessibility: .granted,
                inputMonitoring: .granted
            ),
            model: .ready(modelID: "ggml-small.en-q5_1"),
            blockers: [.microphonePermissionDenied]
        )

        XCTAssertFalse(snapshot.canDictate)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter TextifyRuntimeTests
```

Expected: fails because `TextifyRuntime` target does not exist.

- [ ] **Step 3: Add the package target and products**

Modify `Package.swift`:

```swift
.library(name: "TextifyRuntime", targets: ["TextifyRuntime"]),
```

Add target before the executable target:

```swift
.target(
    name: "TextifyRuntime",
    dependencies: [
        "TextifyCore",
        "TextifyAudio",
        "TextifyTranscription",
        "TextifyModels",
        "TextifyInsertion",
        "TextifyHotkeys",
        "TextifyDiagnostics",
        "TextifySettings"
    ]
),
```

Add `"TextifyRuntime"` to the `Textify` executable target dependencies.

Add test target:

```swift
.testTarget(name: "TextifyRuntimeTests", dependencies: ["TextifyRuntime"]),
```

- [ ] **Step 4: Add runtime contract files**

Create `Sources/TextifyRuntime/TextifyRuntime.swift`:

```swift
public enum TextifyRuntimeModule {
    public static let name = "TextifyRuntime"
}
```

Create `Sources/TextifyRuntime/Readiness/ReadinessSnapshot.swift` using the shared type contracts from this plan.

Create `Sources/TextifyRuntime/Dictation/DictationRuntimeStatus.swift` using the shared type contracts from this plan.

Create `Sources/TextifyRuntime/Dictation/ProductionDictationError.swift` using the shared type contracts from this plan.

Create `Sources/TextifyRuntime/Protocols/RuntimeDependencies.swift`:

```swift
import TextifyAudio
import TextifyCore
import TextifyDiagnostics
import TextifyInsertion
import TextifyModels
import TextifySettings
import TextifyTranscription

public struct RuntimeDependencies: Sendable {
    public let settings: any RuntimeSettingsProviding
    public let permissions: any RuntimePermissionChecking
    public let models: any RuntimeModelResolving
    public let audio: any RuntimeAudioRecording
    public let transcriber: any RuntimeTranscribing
    public let inserter: any InsertionService
    public let diagnostics: any RuntimeDiagnosticsLogging
    public let postProcessor: any RuntimePostProcessing
    public let clock: any RuntimeClock

    public init(
        settings: any RuntimeSettingsProviding,
        permissions: any RuntimePermissionChecking,
        models: any RuntimeModelResolving,
        audio: any RuntimeAudioRecording,
        transcriber: any RuntimeTranscribing,
        inserter: any InsertionService,
        diagnostics: any RuntimeDiagnosticsLogging,
        postProcessor: any RuntimePostProcessing,
        clock: any RuntimeClock
    ) {
        self.settings = settings
        self.permissions = permissions
        self.models = models
        self.audio = audio
        self.transcriber = transcriber
        self.inserter = inserter
        self.diagnostics = diagnostics
        self.postProcessor = postProcessor
        self.clock = clock
    }
}
```

Create `Sources/TextifyRuntime/Dictation/AppDictationService.swift` as a compiling shell:

```swift
import TextifyHotkeys

@MainActor
public final class AppDictationService {
    public private(set) var status: DictationRuntimeStatus
    public private(set) var readiness: ReadinessSnapshot

    private let dependencies: RuntimeDependencies
    private var triggerStateMachine: TriggerStateMachine

    public init(
        dependencies: RuntimeDependencies,
        triggerStateMachine: TriggerStateMachine = TriggerStateMachine()
    ) {
        self.dependencies = dependencies
        self.triggerStateMachine = triggerStateMachine
        self.status = .idle
        self.readiness = ReadinessSnapshot(
            permissions: RuntimePermissionSnapshot(
                microphone: .unknown,
                accessibility: .unknown,
                inputMonitoring: .unknown
            ),
            model: .noActiveModel,
            blockers: [.noActiveModel]
        )
    }

    @discardableResult
    public func refreshReadiness() async -> ReadinessSnapshot {
        let preferences = await dependencies.settings.loadPreferences()
        let permissions = await dependencies.permissions.permissionSnapshot()
        let activeModel = await dependencies.models.resolveActiveModel(preferences: preferences)
        let modelReadiness = await dependencies.models.readiness(for: activeModel)
        let snapshot = ReadinessSnapshot(
            permissions: permissions,
            model: modelReadiness,
            blockers: Self.blockers(permissions: permissions, model: modelReadiness)
        )
        readiness = snapshot
        return snapshot
    }

    @discardableResult
    public func handleTriggerEvent(_ event: TriggerEvent) async -> TriggerAction {
        let action = triggerStateMachine.handle(event)
        await handleTriggerAction(action)
        return action
    }

    public func handleTriggerAction(_ action: TriggerAction) async {
        switch action {
        case .none:
            return
        case .startActivationTimer(_):
            status = .waitingForActivation
        case .beginRecording:
            status = .recording(speechDetected: false)
        case .cancelAsShortcut:
            status = .cancelled(.shortcutUseBeforeSpeech)
        case .cancelRecording:
            status = .cancelled(.escapeKey)
        case .discardRecording:
            status = .idle
        case .finishRecording:
            status = .processing
        }
    }

    public func cancelActiveSession(reason: DictationCancellationReason) async {
        await dependencies.audio.discardRecording()
        status = .cancelled(reason)
    }

    private static func blockers(
        permissions: RuntimePermissionSnapshot,
        model: RuntimeModelReadiness
    ) -> [ReadinessBlocker] {
        var blockers: [ReadinessBlocker] = []
        if permissions.microphone == .denied { blockers.append(.microphonePermissionDenied) }
        if permissions.accessibility == .denied { blockers.append(.accessibilityPermissionDenied) }
        if permissions.inputMonitoring != .granted { blockers.append(.inputMonitoringPermissionDenied) }
        switch model {
        case .ready:
            break
        case let .loading(modelID), let .warming(modelID):
            blockers.append(.activeModelNotReady(modelID: modelID))
        case .noActiveModel:
            blockers.append(.noActiveModel)
        case let .missing(modelID):
            blockers.append(.activeModelMissing(modelID: modelID))
        case let .failed(modelID, _):
            blockers.append(.transcriptionRuntimeFailed(modelID: modelID))
        }
        return blockers
    }
}
```

- [ ] **Step 5: Verify tests pass**

Run:

```bash
swift test --filter TextifyRuntimeTests
swift test
```

Expected: all tests pass.

- [ ] **Step 6: Verify dependency direction**

Run:

```bash
rg -n "import TextifyRuntime" Sources/TextifyAudio Sources/TextifyCore Sources/TextifyDiagnostics Sources/TextifyHotkeys Sources/TextifyInsertion Sources/TextifyModels Sources/TextifySettings Sources/TextifyTranscription
```

Expected: no output.

- [ ] **Step 7: Record coordination note and commit**

Append to `docs/implementation/coordination.md`:

```markdown
## V1.1 Runtime Target

- Added `TextifyRuntime` as the production orchestration target.
- Domain targets must not import `TextifyRuntime`; `TextifyRuntime` adapts domain primitives.
- `AppDictationService` is `@MainActor` because SwiftUI observes its status and readiness.
```

Commit:

```bash
git add Package.swift Sources/TextifyRuntime Tests/TextifyRuntimeTests docs/implementation/coordination.md
git commit -m "v1.1: add runtime orchestration target"
```

## Task 1: TextifyAudio Live AVAudioEngine Capture

**Files:**

- Create: `Sources/TextifyAudio/LiveCapture/LiveAudioRecorder.swift`
- Create: `Sources/TextifyAudio/LiveCapture/LiveAudioRecordingConfiguration.swift`
- Create: `Sources/TextifyAudio/LiveCapture/LiveAudioRecorderError.swift`
- Create: `Sources/TextifyAudio/LiveCapture/MicrophonePermissionClient.swift`
- Create: `Sources/TextifyAudio/LiveCapture/CanonicalAudioConverter.swift`
- Create: `Sources/TextifyAudio/LiveCapture/RMSFrameEmitter.swift`
- Create: `Sources/TextifyAudio/LiveCapture/AudioEngineClient.swift`
- Create: `Sources/TextifyAudio/LiveCapture/SystemAudioEngineClient.swift`
- Create: `Tests/TextifyAudioTests/LiveAudioRecorderTests.swift`
- Create: `Tests/TextifyAudioTests/CanonicalAudioConverterTests.swift`
- Create: `Tests/TextifyAudioTests/RMSFrameEmitterTests.swift`
- Create: `Tests/TextifyAudioTests/MicrophonePermissionClientTests.swift`

- [ ] **Step 1: Write failing audio tests**

Create `Tests/TextifyAudioTests/RMSFrameEmitterTests.swift`:

```swift
import TextifyAudio
import XCTest

final class RMSFrameEmitterTests: XCTestCase {
    func testFiresAfterSustainedSpeech() {
        var emitter = RMSFrameEmitter()
        var detected = false
        for _ in 0..<4 {
            detected = emitter.ingest(samples: Array(repeating: 0.001, count: 320), sampleRate: 16_000)
        }
        for _ in 0..<6 {
            detected = emitter.ingest(samples: Array(repeating: 0.2, count: 320), sampleRate: 16_000)
        }
        XCTAssertTrue(detected)
    }

    func testIgnoresShortSpike() {
        var emitter = RMSFrameEmitter()
        XCTAssertFalse(emitter.ingest(samples: Array(repeating: 0.8, count: 320), sampleRate: 16_000))
    }
}
```

Create `Tests/TextifyAudioTests/LiveAudioRecorderTests.swift` with fake engine seams:

```swift
import AVFoundation
@testable import TextifyAudio
import XCTest

final class LiveAudioRecorderTests: XCTestCase {
    func testDeniedMicrophonePermissionPreventsEngineStart() async throws {
        let permission = MicrophonePermissionClient(
            status: { .denied },
            requestAccess: { .denied }
        )
        let engine = FakeAudioEngineClient()
        let recorder = LiveAudioRecorder(permissionClient: permission, engineClient: engine)

        do {
            try await recorder.startRecording(onSpeechDetected: {}, onMaximumDurationReached: {})
            XCTFail("Expected microphone permission denial")
        } catch let error as LiveAudioRecorderError {
            XCTAssertEqual(error, .microphonePermissionDenied)
        }
        XCTAssertFalse(engine.started)
    }
}
```

Include this fake in the test file:

```swift
final class FakeAudioEngineClient: AudioEngineClient {
    var started = false
    var stopped = false
    var tapInstalled = false

    func start() throws { started = true }
    func stop() { stopped = true }
    func reset() {}
    func installTap(_ handler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
        tapInstalled = true
    }
    func removeTap() { tapInstalled = false }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter TextifyAudioTests
```

Expected: fails because `RMSFrameEmitter`, `MicrophonePermissionClient`, `LiveAudioRecorder`, and `AudioEngineClient` do not exist.

- [ ] **Step 3: Add public live capture API**

Create `LiveAudioRecordingConfiguration.swift`:

```swift
public enum LiveAudioInput: Equatable, Sendable {
    case systemDefault
}

public struct LiveAudioRecordingConfiguration: Equatable, Sendable {
    public let input: LiveAudioInput
    public let maximumDurationSeconds: Double
    public let postReleaseGraceMilliseconds: Int

    public init(
        input: LiveAudioInput = .systemDefault,
        maximumDurationSeconds: Double = 60,
        postReleaseGraceMilliseconds: Int = 250
    ) {
        self.input = input
        self.maximumDurationSeconds = maximumDurationSeconds
        self.postReleaseGraceMilliseconds = postReleaseGraceMilliseconds
    }

    public static let v1_1Default = LiveAudioRecordingConfiguration()
}
```

Create `LiveAudioRecorderError.swift`:

```swift
public enum LiveAudioRecorderError: Error, Equatable, Sendable {
    case microphonePermissionDenied
    case unsupportedInput
    case alreadyRecording
    case notRecording
    case inputNodeUnavailable
    case unsupportedInputFormat
    case engineStartFailed
    case conversionFailed
    case emptyRecording
    case deviceChangedDuringRecording
}
```

Create `MicrophonePermissionClient.swift`:

```swift
import AVFoundation

public enum MicrophonePermissionStatus: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
}

public struct MicrophonePermissionClient: Sendable {
    private let statusClosure: @Sendable () -> MicrophonePermissionStatus
    private let requestClosure: @Sendable () async -> MicrophonePermissionStatus

    public init(
        status: @escaping @Sendable () -> MicrophonePermissionStatus,
        requestAccess: @escaping @Sendable () async -> MicrophonePermissionStatus
    ) {
        self.statusClosure = status
        self.requestClosure = requestAccess
    }

    public func status() -> MicrophonePermissionStatus { statusClosure() }
    public func requestAccess() async -> MicrophonePermissionStatus { await requestClosure() }

    public static let live = MicrophonePermissionClient(
        status: {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            case .denied: return .denied
            case .restricted: return .restricted
            @unknown default: return .denied
            }
        },
        requestAccess: {
            await AVCaptureDevice.requestAccess(for: .audio) ? .granted : .denied
        }
    )
}
```

- [ ] **Step 4: Add engine seam and recorder**

Create `AudioEngineClient.swift`:

```swift
import AVFoundation

public protocol AudioEngineClient: AnyObject {
    func start() throws
    func stop()
    func reset()
    func installTap(_ handler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) throws
    func removeTap()
}
```

Create `SystemAudioEngineClient.swift`:

```swift
import AVFoundation

public final class SystemAudioEngineClient: AudioEngineClient {
    private let engine = AVAudioEngine()

    public init() {}

    public func start() throws {
        try engine.start()
    }

    public func stop() {
        engine.stop()
    }

    public func reset() {
        engine.reset()
    }

    public func installTap(_ handler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw LiveAudioRecorderError.unsupportedInputFormat
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
            handler(buffer, time)
        }
    }

    public func removeTap() {
        engine.inputNode.removeTap(onBus: 0)
    }
}
```

Create `RMSFrameEmitter.swift`:

```swift
public struct RMSFrameEmitter: Sendable {
    private let threshold: Float
    private let requiredSpeechFrames: Int
    private var speechFrames = 0
    private var hasEmitted = false

    public init(threshold: Float = 0.02, requiredSpeechFrames: Int = 5) {
        self.threshold = threshold
        self.requiredSpeechFrames = requiredSpeechFrames
    }

    public mutating func ingest(samples: [Float], sampleRate: Int) -> Bool {
        guard !samples.isEmpty, sampleRate > 0, !hasEmitted else {
            return false
        }
        let sumSquares = samples.reduce(Float(0)) { $0 + ($1 * $1) }
        let rms = (sumSquares / Float(samples.count)).squareRoot()
        if rms >= threshold {
            speechFrames += 1
        } else {
            speechFrames = 0
        }
        if speechFrames >= requiredSpeechFrames {
            hasEmitted = true
            return true
        }
        return false
    }
}
```

Create `CanonicalAudioConverter.swift`:

```swift
import AVFoundation

public struct CanonicalAudioConverter: Sendable {
    public init() {}

    public func convert(_ buffer: AVAudioPCMBuffer) throws -> CanonicalAudioBuffer {
        guard let channelData = buffer.floatChannelData else {
            throw LiveAudioRecorderError.unsupportedInputFormat
        }
        let sourceFrameCount = Int(buffer.frameLength)
        guard sourceFrameCount > 0 else {
            return CanonicalAudioBuffer(samples: [])
        }
        let sourceRate = Int(buffer.format.sampleRate)
        guard sourceRate > 0 else {
            throw LiveAudioRecorderError.unsupportedInputFormat
        }
        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else {
            throw LiveAudioRecorderError.unsupportedInputFormat
        }

        var mono = [Float](repeating: 0, count: sourceFrameCount)
        for frame in 0..<sourceFrameCount {
            var sum: Float = 0
            for channel in 0..<channelCount {
                sum += channelData[channel][frame]
            }
            mono[frame] = sum / Float(channelCount)
        }

        guard sourceRate != 16_000 else {
            return CanonicalAudioBuffer(sampleRate: 16_000, channelCount: 1, samples: mono)
        }

        let ratio = Double(16_000) / Double(sourceRate)
        let outputCount = max(0, Int(Double(mono.count) * ratio))
        var resampled = [Float]()
        resampled.reserveCapacity(outputCount)
        for index in 0..<outputCount {
            let sourcePosition = Double(index) / ratio
            let lower = min(Int(sourcePosition), mono.count - 1)
            let upper = min(lower + 1, mono.count - 1)
            let fraction = Float(sourcePosition - Double(lower))
            resampled.append(mono[lower] + (mono[upper] - mono[lower]) * fraction)
        }
        return CanonicalAudioBuffer(sampleRate: 16_000, channelCount: 1, samples: resampled)
    }
}
```

Create `LiveAudioRecorder.swift`:

```swift
import AVFoundation

public actor LiveAudioRecorder {
    private let permissionClient: MicrophonePermissionClient
    private let configuration: LiveAudioRecordingConfiguration
    private let engineClient: AudioEngineClient
    private var isRecording = false
    private var capturedSamples: [Float] = []
    private var speechDetected = false

    public init(
        permissionClient: MicrophonePermissionClient = .live,
        configuration: LiveAudioRecordingConfiguration = .v1_1Default,
        engineClient: AudioEngineClient = SystemAudioEngineClient()
    ) {
        self.permissionClient = permissionClient
        self.configuration = configuration
        self.engineClient = engineClient
    }

    public func startRecording(
        onSpeechDetected: @escaping @Sendable () -> Void,
        onMaximumDurationReached: @escaping @Sendable () -> Void
    ) async throws {
        guard permissionClient.status() == .granted else {
            throw LiveAudioRecorderError.microphonePermissionDenied
        }
        guard !isRecording else {
            throw LiveAudioRecorderError.alreadyRecording
        }
        isRecording = true
        capturedSamples.removeAll(keepingCapacity: true)
        speechDetected = false
        do {
            try engineClient.installTap { _, _ in
                onSpeechDetected()
            }
            try engineClient.start()
        } catch let error as LiveAudioRecorderError {
            isRecording = false
            throw error
        } catch {
            isRecording = false
            throw LiveAudioRecorderError.engineStartFailed
        }
    }

    public func finishRecording() async throws -> CanonicalAudioBuffer {
        guard isRecording else {
            throw LiveAudioRecorderError.notRecording
        }
        engineClient.removeTap()
        engineClient.stop()
        isRecording = false
        let buffer = CanonicalAudioBuffer(samples: capturedSamples)
        guard !buffer.isEmpty else {
            throw LiveAudioRecorderError.emptyRecording
        }
        capturedSamples.removeAll(keepingCapacity: false)
        return buffer
    }

    public func discardRecording() async {
        if isRecording {
            engineClient.removeTap()
            engineClient.stop()
        }
        isRecording = false
        capturedSamples.removeAll(keepingCapacity: false)
    }
}
```

Add these stored properties to `LiveAudioRecorder`:

```swift
private let converter = CanonicalAudioConverter()
private var rmsEmitter = RMSFrameEmitter()
```

Replace the temporary tap body with actor-isolated conversion and RMS ingestion:

```swift
try engineClient.installTap { [weak self] buffer, _ in
    Task { await self?.ingest(buffer, onSpeechDetected: onSpeechDetected) }
}
```

Add this helper inside `LiveAudioRecorder` so the escaping tap closure does not mutate actor state directly:

```swift
private func ingest(
    _ buffer: AVAudioPCMBuffer,
    onSpeechDetected: @escaping @Sendable () -> Void
) {
    do {
        let canonical = try converter.convert(buffer)
        capturedSamples.append(contentsOf: canonical.samples)
        if rmsEmitter.ingest(samples: canonical.samples, sampleRate: canonical.sampleRate) {
            speechDetected = true
            onSpeechDetected()
        }
    } catch {
        engineClient.removeTap()
        engineClient.stop()
        isRecording = false
    }
}
```

- [ ] **Step 5: Verify focused and full tests**

Run:

```bash
swift test --filter TextifyAudioTests
swift test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/TextifyAudio Tests/TextifyAudioTests
git commit -m "v1.1: add live audio capture"
```

## Task 2: TextifyHotkeys CGEventTap Right Command Path

**Files:**

- Create: `Sources/TextifyHotkeys/GlobalHotkeyMonitor.swift`
- Create: `Sources/TextifyHotkeys/HotkeyMonitorError.swift`
- Create: `Sources/TextifyHotkeys/InputMonitoringPermissionClient.swift`
- Create: `Sources/TextifyHotkeys/KeyboardEventSnapshot.swift`
- Create: `Sources/TextifyHotkeys/TriggerEventMapper.swift`
- Create: `Sources/TextifyHotkeys/TriggerKeyMatcher.swift`
- Create: `Sources/TextifyHotkeys/CGEventTapClient.swift`
- Create: `Sources/TextifyHotkeys/TriggerTestSession.swift`
- Create: `Tests/TextifyHotkeysTests/TriggerEventMapperTests.swift`
- Create: `Tests/TextifyHotkeysTests/GlobalHotkeyMonitorTests.swift`
- Create: `Tests/TextifyHotkeysTests/InputMonitoringPermissionClientTests.swift`
- Create: `Tests/TextifyHotkeysTests/TriggerTestSessionTests.swift`

- [ ] **Step 1: Write failing mapper tests**

Create `Tests/TextifyHotkeysTests/TriggerEventMapperTests.swift`:

```swift
import TextifyHotkeys
import XCTest

final class TriggerEventMapperTests: XCTestCase {
    func testRightCommandDownMapsToTriggerDown() {
        var mapper = TriggerEventMapper(trigger: .rightCommand)
        let event = KeyboardEventSnapshot(
            type: .flagsChanged,
            keyCode: TriggerKeyMatcher.rightCommandKeyCode,
            flags: TriggerKeyMatcher.commandFlagMask,
            timestampMs: 100,
            isAutoRepeat: false
        )

        XCTAssertEqual(mapper.map(event), .triggerDown(timestampMs: 100))
    }

    func testLeftCommandIsIgnored() {
        var mapper = TriggerEventMapper(trigger: .rightCommand)
        let event = KeyboardEventSnapshot(
            type: .flagsChanged,
            keyCode: TriggerKeyMatcher.leftCommandKeyCode,
            flags: TriggerKeyMatcher.commandFlagMask,
            timestampMs: 100,
            isAutoRepeat: false
        )

        XCTAssertNil(mapper.map(event))
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
swift test --filter TriggerEventMapperTests
```

Expected: fails because `TriggerEventMapper`, `KeyboardEventSnapshot`, and `TriggerKeyMatcher` do not exist.

- [ ] **Step 3: Add pure mapping types**

Create `KeyboardEventSnapshot.swift`:

```swift
public struct KeyboardEventSnapshot: Equatable, Sendable {
    public enum EventType: Equatable, Sendable {
        case flagsChanged
        case keyDown
    }

    public let type: EventType
    public let keyCode: UInt16
    public let flags: UInt64
    public let timestampMs: Int
    public let isAutoRepeat: Bool

    public init(type: EventType, keyCode: UInt16, flags: UInt64, timestampMs: Int, isAutoRepeat: Bool) {
        self.type = type
        self.keyCode = keyCode
        self.flags = flags
        self.timestampMs = timestampMs
        self.isAutoRepeat = isAutoRepeat
    }
}
```

Create `TriggerKeyMatcher.swift`:

```swift
public enum TriggerKeyMatcher {
    public static let rightCommandKeyCode: UInt16 = 54
    public static let leftCommandKeyCode: UInt16 = 55
    public static let escapeKeyCode: UInt16 = 53
    public static let commandFlagMask: UInt64 = 1 << 20
}
```

Create `TriggerEventMapper.swift` with duplicate protection:

```swift
public struct TriggerEventMapper: Sendable {
    private let trigger: TriggerPreference
    private var rightCommandDown = false

    public init(trigger: TriggerPreference = .rightCommand) {
        self.trigger = trigger
    }

    public mutating func map(_ event: KeyboardEventSnapshot) -> TriggerEvent? {
        guard trigger == .rightCommand else {
            return nil
        }
        if event.type == .keyDown, event.keyCode == TriggerKeyMatcher.escapeKeyCode {
            return .escapeKeyDown(timestampMs: event.timestampMs)
        }
        if event.type == .keyDown, rightCommandDown {
            return .nonTriggerKeyDown(timestampMs: event.timestampMs, isModifierOnly: false)
        }
        guard event.type == .flagsChanged else {
            return nil
        }
        if event.keyCode == TriggerKeyMatcher.leftCommandKeyCode {
            return nil
        }
        if event.keyCode == TriggerKeyMatcher.rightCommandKeyCode {
            let commandPresent = (event.flags & TriggerKeyMatcher.commandFlagMask) != 0
            if commandPresent, !rightCommandDown {
                rightCommandDown = true
                return .triggerDown(timestampMs: event.timestampMs)
            }
            if !commandPresent, rightCommandDown {
                rightCommandDown = false
                return .triggerUp(timestampMs: event.timestampMs)
            }
            return nil
        }
        if rightCommandDown {
            return .nonTriggerKeyDown(timestampMs: event.timestampMs, isModifierOnly: true)
        }
        return nil
    }
}
```

- [ ] **Step 4: Add monitor and trigger test APIs**

Create `InputMonitoringPermissionClient.swift`:

```swift
import CoreGraphics

public enum InputMonitoringPermissionStatus: Equatable, Sendable {
    case unknown
    case granted
    case denied
}

public struct InputMonitoringPermissionClient: Sendable {
    private let statusClosure: @Sendable () -> InputMonitoringPermissionStatus
    private let requestClosure: @Sendable () async -> InputMonitoringPermissionStatus

    public init(
        status: @escaping @Sendable () -> InputMonitoringPermissionStatus,
        requestAccess: @escaping @Sendable () async -> InputMonitoringPermissionStatus
    ) {
        self.statusClosure = status
        self.requestClosure = requestAccess
    }

    public func status() -> InputMonitoringPermissionStatus { statusClosure() }
    public func requestAccess() async -> InputMonitoringPermissionStatus { await requestClosure() }

    public static let live = InputMonitoringPermissionClient(
        status: {
            CGPreflightListenEventAccess() ? .granted : .unknown
        },
        requestAccess: {
            CGRequestListenEventAccess() ? .granted : .denied
        }
    )
}
```

Create `HotkeyMonitorError.swift`:

```swift
public enum HotkeyMonitorError: Error, Equatable, Sendable {
    case inputMonitoringDenied
    case eventTapCreationFailed
    case runLoopSourceCreationFailed
    case alreadyRunning
    case notRunning
}
```

Create `CGEventTapClient.swift`:

```swift
import CoreGraphics
import Foundation

public struct CGEventTapHandle: @unchecked Sendable {
    let port: CFMachPort
    let source: CFRunLoopSource
    let refcon: UnsafeMutableRawPointer
}

public protocol CGEventTapClient: Sendable {
    func start(handler: @escaping @Sendable (KeyboardEventSnapshot) -> Void) throws -> CGEventTapHandle
    func stop(_ handle: CGEventTapHandle)
}

public final class SystemCGEventTapClient: CGEventTapClient, @unchecked Sendable {
    public init() {}

    public func start(handler: @escaping @Sendable (KeyboardEventSnapshot) -> Void) throws -> CGEventTapHandle {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let box = EventHandlerBox(handler: handler)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let box = Unmanaged<EventHandlerBox>.fromOpaque(refcon).takeUnretainedValue()
                if let snapshot = KeyboardEventSnapshot(event: event, type: type) {
                    box.handler(snapshot)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            Unmanaged<EventHandlerBox>.fromOpaque(refcon).release()
            throw HotkeyMonitorError.eventTapCreationFailed
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            Unmanaged<EventHandlerBox>.fromOpaque(refcon).release()
            throw HotkeyMonitorError.runLoopSourceCreationFailed
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return CGEventTapHandle(port: port, source: source, refcon: refcon)
    }

    public func stop(_ handle: CGEventTapHandle) {
        CGEvent.tapEnable(tap: handle.port, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), handle.source, .commonModes)
        CFMachPortInvalidate(handle.port)
        Unmanaged<EventHandlerBox>.fromOpaque(handle.refcon).release()
    }
}

private final class EventHandlerBox {
    let handler: @Sendable (KeyboardEventSnapshot) -> Void
    init(handler: @escaping @Sendable (KeyboardEventSnapshot) -> Void) {
        self.handler = handler
    }
}
```

Add this initializer to `KeyboardEventSnapshot.swift`:

```swift
import CoreGraphics

public extension KeyboardEventSnapshot {
    init?(event: CGEvent, type: CGEventType) {
        let mappedType: EventType
        switch type {
        case .flagsChanged:
            mappedType = .flagsChanged
        case .keyDown:
            mappedType = .keyDown
        default:
            return nil
        }
        self.init(
            type: mappedType,
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags.rawValue,
            timestampMs: Int(event.timestamp / 1_000_000),
            isAutoRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        )
    }
}
```

Create `GlobalHotkeyMonitor.swift`:

```swift
public final class GlobalHotkeyMonitor: @unchecked Sendable {
    private let permissionClient: InputMonitoringPermissionClient
    private let eventTapClient: any CGEventTapClient
    private var mapper: TriggerEventMapper
    private var handle: CGEventTapHandle?

    public init(
        permissionClient: InputMonitoringPermissionClient = .live,
        eventTapClient: any CGEventTapClient = SystemCGEventTapClient(),
        trigger: TriggerPreference = .defaultTrigger
    ) {
        self.permissionClient = permissionClient
        self.eventTapClient = eventTapClient
        self.mapper = TriggerEventMapper(trigger: trigger)
    }

    public func start(
        onEvent: @escaping @Sendable (TriggerEvent) -> Void,
        onFailure: @escaping @Sendable (HotkeyMonitorError) -> Void
    ) {
        guard handle == nil else {
            onFailure(.alreadyRunning)
            return
        }
        guard permissionClient.status() != .denied else {
            onFailure(.inputMonitoringDenied)
            return
        }
        do {
            handle = try eventTapClient.start { [weak self] snapshot in
                guard let self, let event = self.mapper.map(snapshot) else { return }
                onEvent(event)
            }
        } catch let error as HotkeyMonitorError {
            onFailure(error)
        } catch {
            onFailure(.eventTapCreationFailed)
        }
    }

    public func stop() {
        guard let handle else { return }
        eventTapClient.stop(handle)
        self.handle = nil
    }
}
```

Create `TriggerTestSession.swift`:

```swift
public struct TriggerTestSessionResult: Equatable, Sendable {
    public let sawDown: Bool
    public let sawBeginRecording: Bool
    public let sawUp: Bool
    public var passed: Bool { sawDown && sawBeginRecording && sawUp }
}

public actor TriggerTestSession {
    private var stateMachine = TriggerStateMachine()
    private var sawDown = false
    private var sawBeginRecording = false
    private var sawUp = false

    public init() {}

    public func ingest(_ event: TriggerEvent) -> TriggerTestSessionResult {
        if case .triggerDown = event { sawDown = true }
        if case .triggerUp = event { sawUp = true }
        let action = stateMachine.handle(event)
        if action == .beginRecording { sawBeginRecording = true }
        return TriggerTestSessionResult(
            sawDown: sawDown,
            sawBeginRecording: sawBeginRecording,
            sawUp: sawUp
        )
    }
}
```

- [ ] **Step 5: Verify tests**

```bash
swift test --filter TextifyHotkeysTests
swift test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/TextifyHotkeys Tests/TextifyHotkeysTests
git commit -m "v1.1: add right command hotkey monitor"
```

## Task 3: TextifyInsertion PasteInsertionService

**Files:**

- Modify: `Sources/TextifyInsertion/InsertionService.swift`
- Modify: `Sources/TextifyInsertion/PasteboardClient.swift`
- Modify: `Sources/TextifyInsertion/EventPoster.swift`
- Create: `Sources/TextifyInsertion/InsertionFailureReason.swift`
- Create: `Sources/TextifyInsertion/PasteInsertionService.swift`
- Create: `Sources/TextifyInsertion/PasteboardMarker.swift`
- Create: `Sources/TextifyInsertion/AccessibilityTrustClient.swift`
- Create: `Sources/TextifyInsertion/InsertionTargetChecker.swift`
- Create: `Sources/TextifyInsertion/SystemInsertionTargetChecker.swift`
- Create: `Sources/TextifyInsertion/SystemPasteboardClient.swift`
- Create: `Sources/TextifyInsertion/SystemEventPoster.swift`
- Create: `Tests/TextifyInsertionTests/PasteInsertionServiceTests.swift`
- Create: `Tests/TextifyInsertionTests/PasteboardMarkerTests.swift`
- Create: `Tests/TextifyInsertionTests/InsertionTargetCheckerTests.swift`

- [ ] **Step 1: Write failing paste service tests**

Create `Tests/TextifyInsertionTests/PasteInsertionServiceTests.swift`:

```swift
import TextifyInsertion
import XCTest

final class PasteInsertionServiceTests: XCTestCase {
    func testEmptyTextTouchesNothing() async {
        let pasteboard = FakePasteboardClient()
        let poster = FakeEventPoster()
        let service = PasteInsertionService(
            pasteboard: pasteboard,
            eventPoster: poster,
            accessibility: AccessibilityTrustClient(status: { .trusted }),
            targetChecker: FakeTargetChecker(status: .allowed),
            restoreDelayMilliseconds: 0
        )

        let outcome = await service.insert(InsertionRequest(text: ""))

        XCTAssertEqual(outcome, .notInserted(.emptyText))
        XCTAssertEqual(pasteboard.snapshotCount, 0)
        XCTAssertEqual(poster.pasteCount, 0)
    }

    func testSuccessfulPasteRestoresWhenMarkerStillPresent() async {
        let pasteboard = FakePasteboardClient(markerStillPresent: true)
        let poster = FakeEventPoster()
        let service = PasteInsertionService(
            pasteboard: pasteboard,
            eventPoster: poster,
            accessibility: AccessibilityTrustClient(status: { .trusted }),
            targetChecker: FakeTargetChecker(status: .allowed),
            restoreDelayMilliseconds: 0
        )

        let outcome = await service.insert(InsertionRequest(text: "hello"))

        XCTAssertEqual(poster.pasteCount, 1)
        XCTAssertEqual(outcome, .pasted(PasteInsertionReport(pasteboardRestored: true, pasteboardRestoreFailed: false)))
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
swift test --filter PasteInsertionServiceTests
```

Expected: fails because production insertion types do not exist.

- [ ] **Step 3: Replace insertion result types**

Modify `InsertionService.swift`:

```swift
public struct InsertionRequest: Equatable, Sendable {
    public let text: String
    public init(text: String) {
        self.text = text
    }
}

public enum InsertionOutcome: Equatable, Sendable {
    case pasted(PasteInsertionReport)
    case notInserted(InsertionFailureReason)
}

public struct PasteInsertionReport: Equatable, Sendable {
    public let pasteboardRestored: Bool
    public let pasteboardRestoreFailed: Bool

    public init(pasteboardRestored: Bool, pasteboardRestoreFailed: Bool) {
        self.pasteboardRestored = pasteboardRestored
        self.pasteboardRestoreFailed = pasteboardRestoreFailed
    }
}

public protocol InsertionService: Sendable {
    func insert(_ request: InsertionRequest) async -> InsertionOutcome
}
```

Create `InsertionFailureReason.swift`:

```swift
public enum InsertionFailureReason: Error, Equatable, Sendable {
    case emptyText
    case accessibilityNotTrusted
    case blockedTarget(InsertionTargetBlock)
    case pasteboardSnapshotFailed
    case pasteboardWriteFailed
    case pasteEventFailed
}
```

- [ ] **Step 4: Add pasteboard marker and protocol changes**

Create `PasteboardMarker.swift`:

```swift
import Foundation

public struct PasteboardMarker: Equatable, Sendable {
    public let uuid: UUID
    public static let pasteboardType = "io.github.Player0109.Textify.private-marker"

    public init(uuid: UUID = UUID()) {
        self.uuid = uuid
    }
}
```

Modify `PasteboardClient.swift`:

```swift
public protocol PasteboardClient: Sendable {
    func snapshot() async throws -> PasteboardSnapshot
    func clearAndWritePlainText(_ text: String, marker: PasteboardMarker) async throws -> PasteboardWriteResult
    func containsMarker(_ marker: PasteboardMarker) async throws -> Bool
    func restore(_ snapshot: PasteboardSnapshot) async throws
}
```

Modify `EventPoster.swift`:

```swift
public protocol EventPoster: Sendable {
    func postPasteCommand() async throws
}
```

- [ ] **Step 5: Add target checks and service**

Create `AccessibilityTrustClient.swift`:

```swift
import ApplicationServices

public enum AccessibilityTrustStatus: Equatable, Sendable {
    case trusted
    case notTrusted
}

public struct AccessibilityTrustClient: Sendable {
    private let statusClosure: @Sendable () -> AccessibilityTrustStatus

    public init(status: @escaping @Sendable () -> AccessibilityTrustStatus) {
        self.statusClosure = status
    }

    public func status() -> AccessibilityTrustStatus { statusClosure() }

    public static let live = AccessibilityTrustClient(
        status: {
            AXIsProcessTrusted() ? .trusted : .notTrusted
        }
    )
}
```

Create `InsertionTargetChecker.swift`:

```swift
public enum InsertionTargetStatus: Equatable, Sendable {
    case allowed
    case blocked(InsertionTargetBlock)
}

public enum InsertionTargetBlock: Equatable, Sendable {
    case secureInputEnabled
    case secureFieldFocused
    case systemOwnedContext
    case noFocusedElement
    case unsupportedFocusedElement
}

public protocol InsertionTargetChecking: Sendable {
    func currentTargetStatus() async -> InsertionTargetStatus
}
```

Create `SystemInsertionTargetChecker.swift`:

```swift
import ApplicationServices
import Carbon.HIToolbox

public struct SystemInsertionTargetChecker: InsertionTargetChecking {
    public init() {}

    public func currentTargetStatus() async -> InsertionTargetStatus {
        guard !IsSecureEventInputEnabled() else {
            return .blocked(.secureInputEnabled)
        }
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard result == .success, focused != nil else {
            return .blocked(.noFocusedElement)
        }
        return .allowed
    }
}
```

Create `PasteInsertionService.swift` implementing the insertion flow from the V1.1 grill:

```swift
public actor PasteInsertionService: InsertionService {
    private let pasteboard: any PasteboardClient
    private let eventPoster: any EventPoster
    private let accessibility: AccessibilityTrustClient
    private let targetChecker: any InsertionTargetChecking
    private let restoreDelayMilliseconds: Int

    public init(
        pasteboard: any PasteboardClient,
        eventPoster: any EventPoster,
        accessibility: AccessibilityTrustClient,
        targetChecker: any InsertionTargetChecking,
        restoreDelayMilliseconds: Int = 150
    ) {
        self.pasteboard = pasteboard
        self.eventPoster = eventPoster
        self.accessibility = accessibility
        self.targetChecker = targetChecker
        self.restoreDelayMilliseconds = restoreDelayMilliseconds
    }

    public func insert(_ request: InsertionRequest) async -> InsertionOutcome {
        guard !request.text.isEmpty else { return .notInserted(.emptyText) }
        guard accessibility.status() == .trusted else { return .notInserted(.accessibilityNotTrusted) }
        let targetStatus = await targetChecker.currentTargetStatus()
        if case let .blocked(block) = targetStatus {
            return .notInserted(.blockedTarget(block))
        }
        let snapshot: PasteboardSnapshot
        do {
            snapshot = try await pasteboard.snapshot()
        } catch {
            return .notInserted(.pasteboardSnapshotFailed)
        }
        let marker = PasteboardMarker()
        do {
            _ = try await pasteboard.clearAndWritePlainText(request.text, marker: marker)
        } catch {
            return .notInserted(.pasteboardWriteFailed)
        }
        do {
            try await eventPoster.postPasteCommand()
        } catch {
            if (try? await pasteboard.containsMarker(marker)) == true {
                try? await pasteboard.restore(snapshot)
            }
            return .notInserted(.pasteEventFailed)
        }
        if (try? await pasteboard.containsMarker(marker)) == true {
            do {
                try await pasteboard.restore(snapshot)
                return .pasted(PasteInsertionReport(pasteboardRestored: true, pasteboardRestoreFailed: false))
            } catch {
                return .pasted(PasteInsertionReport(pasteboardRestored: false, pasteboardRestoreFailed: true))
            }
        }
        return .pasted(PasteInsertionReport(pasteboardRestored: false, pasteboardRestoreFailed: false))
    }
}
```

- [ ] **Step 6: Add system clients**

Create `SystemPasteboardClient.swift`:

```swift
import AppKit
import Foundation

public actor SystemPasteboardClient: PasteboardClient {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func snapshot() async throws -> PasteboardSnapshot {
        let items = pasteboard.pasteboardItems?.map { item in
            var representations: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    representations[type.rawValue] = data
                }
            }
            return PasteboardItemSnapshot(representationsByType: representations)
        } ?? []
        return PasteboardSnapshot(items: items, changeCount: pasteboard.changeCount)
    }

    public func clearAndWritePlainText(_ text: String, marker: PasteboardMarker) async throws -> PasteboardWriteResult {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString(marker.uuid.uuidString, forType: NSPasteboard.PasteboardType(PasteboardMarker.pasteboardType))
        item.setString("1", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        item.setString("1", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        item.setString("1", forType: NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"))
        guard pasteboard.writeObjects([item]) else {
            throw InsertionFailureReason.pasteboardWriteFailed
        }
        return PasteboardWriteResult(changeCount: pasteboard.changeCount)
    }

    public func containsMarker(_ marker: PasteboardMarker) async throws -> Bool {
        let markerType = NSPasteboard.PasteboardType(PasteboardMarker.pasteboardType)
        return pasteboard.pasteboardItems?.contains { item in
            item.string(forType: markerType) == marker.uuid.uuidString
        } ?? false
    }

    public func restore(_ snapshot: PasteboardSnapshot) async throws {
        pasteboard.clearContents()
        let items = snapshot.items.map { snapshotItem -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in snapshotItem.representationsByType {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
```

The system pasteboard client writes:

- `NSPasteboard.PasteboardType.string`
- private type `io.github.Player0109.Textify.private-marker`
- transient/concealed/autogenerated types where supported

Create `SystemEventPoster.swift`:

```swift
import CoreGraphics

public struct SystemEventPoster: EventPoster {
    public init() {}

    public func postPasteCommand() async throws {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw InsertionFailureReason.pasteEventFailed
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 7: Verify tests and update affected fake insertion code**

Run:

```bash
swift test --filter TextifyInsertionTests
swift test
```

Expected: all tests pass. If `Sources/Textify/App/AppServices.swift` fails because it expects `.pastePosted`, update it in the app integration task if this task owns no app files; otherwise add a coordination note and make the minimal compile fix.

- [ ] **Step 8: Commit**

```bash
git add Sources/TextifyInsertion Tests/TextifyInsertionTests docs/implementation/coordination.md
git commit -m "v1.1: add paste insertion service"
```

## Task 4: TextifyModels V1.1 Manifest, Download, And Install

**Files:**

- Modify: `Sources/TextifyModels/Manifest/ModelManifest.swift`
- Modify: `Sources/TextifyModels/Manifest/ManifestSignature.swift`
- Modify: `Sources/TextifyModels/Manifest/ManifestVerifier.swift`
- Create: `Sources/TextifyModels/Manifest/ProductionModelPolicy.swift`
- Create: `Sources/TextifyModels/Storage/ModelStorageLayout.swift`
- Modify: `Sources/TextifyModels/Storage/InstalledModelsStore.swift`
- Modify: `Sources/TextifyModels/Downloads/ModelDownloader.swift`
- Create: `Sources/TextifyModels/Downloads/ModelInstaller.swift`
- Create: `Sources/TextifyModels/Downloads/ModelInstallError.swift`
- Modify: `Tests/TextifyModelsTests/ManifestSignatureTests.swift`
- Modify: `Tests/TextifyModelsTests/ManifestTests.swift`
- Create: `Tests/TextifyModelsTests/ModelInstallerTests.swift`
- Replace: `Tests/TextifyModelsTests/Fixtures/Models/manifest.json`
- Replace: `Tests/TextifyModelsTests/Fixtures/Models/manifest.json.sig`
- Create: `Tests/TextifyModelsTests/Fixtures/Models/model.bin`

- [ ] **Step 1: Write failing manifest signature tests**

Update `Tests/TextifyModelsTests/ManifestSignatureTests.swift` so the primary tests are:

```swift
import CryptoKit
import Foundation
import TextifyModels
import XCTest

final class ManifestSignatureTests: XCTestCase {
    func testVerifierAcceptsSignatureOverExactManifestBytes() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let manifestData = Data(#"{"manifestVersion":1,"generatedAt":"2026-07-03T00:00:00Z","models":[]}"#.utf8)
        let signature = privateKey.signature(for: manifestData).base64EncodedString()
        let signatureData = Data("""
        {"signatureVersion":1,"keyId":"test-key","algorithm":"Ed25519","signatureBase64":"\(signature)"}
        """.utf8)

        let verifier = ManifestVerifier(trustedKeys: [
            TrustedModelManifestKey(keyId: "test-key", publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString())
        ])

        let manifest = try verifier.verify(manifestData: manifestData, signatureData: signatureData)

        XCTAssertEqual(manifest.manifestVersion, 1)
    }

    func testVerifierRejectsWhitespaceChangedAfterSigning() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let signedData = Data(#"{"manifestVersion":1,"generatedAt":"2026-07-03T00:00:00Z","models":[]}"#.utf8)
        let changedData = Data(#"{ "manifestVersion": 1, "generatedAt": "2026-07-03T00:00:00Z", "models": [] }"#.utf8)
        let signature = privateKey.signature(for: signedData).base64EncodedString()
        let signatureData = Data("""
        {"signatureVersion":1,"keyId":"test-key","algorithm":"Ed25519","signatureBase64":"\(signature)"}
        """.utf8)
        let verifier = ManifestVerifier(trustedKeys: [
            TrustedModelManifestKey(keyId: "test-key", publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString())
        ])

        XCTAssertThrowsError(try verifier.verify(manifestData: changedData, signatureData: signatureData))
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
swift test --filter ManifestSignatureTests
```

Expected: fails because `ManifestVerifier(trustedKeys:)`, `TrustedModelManifestKey`, and raw-byte signature verification do not exist.

- [ ] **Step 3: Replace signature schema and verifier**

Modify `ManifestSignature.swift`:

```swift
import Foundation

public struct ManifestSignature: Codable, Equatable, Sendable {
    public let signatureVersion: Int
    public let keyId: String
    public let algorithm: String
    public let signatureBase64: String

    public static func decode(_ data: Data) throws -> ManifestSignature {
        try JSONDecoder().decode(ManifestSignature.self, from: data)
    }
}
```

Modify `ManifestVerifier.swift`:

```swift
import CryptoKit
import Foundation

public struct TrustedModelManifestKey: Equatable, Sendable {
    public let keyId: String
    public let publicKeyBase64: String

    public init(keyId: String, publicKeyBase64: String) {
        self.keyId = keyId
        self.publicKeyBase64 = publicKeyBase64
    }
}

public struct ManifestVerifier {
    public static let algorithm = "Ed25519"
    private let trustedKeys: [TrustedModelManifestKey]

    public init(trustedKeys: [TrustedModelManifestKey]) {
        self.trustedKeys = trustedKeys
    }

    public func verify(manifestData: Data, signatureData: Data) throws -> ModelManifest {
        let signature = try ManifestSignature.decode(signatureData)
        guard signature.signatureVersion == 1 else {
            throw ManifestVerificationError.unsupportedSignatureVersion(signature.signatureVersion)
        }
        guard signature.algorithm == Self.algorithm else {
            throw ManifestVerificationError.unsupportedAlgorithm(signature.algorithm)
        }
        guard let trustedKey = trustedKeys.first(where: { $0.keyId == signature.keyId }) else {
            throw ManifestVerificationError.unknownKeyId(signature.keyId)
        }
        guard let publicKeyData = Data(base64Encoded: trustedKey.publicKeyBase64),
              let signatureData = Data(base64Encoded: signature.signatureBase64) else {
            throw ManifestVerificationError.invalidSignatureEncoding
        }
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        guard publicKey.isValidSignature(signatureData, for: manifestData) else {
            throw ManifestVerificationError.signatureRejected
        }
        return try ModelManifest.decode(manifestData)
    }
}
```

Retain existing error cases that still apply and remove checks for metadata fields that no longer exist.

Update `ModelDownloader` to accept the new verifier shape:

```swift
public struct ModelDownloader {
    private let transport: any DownloadTransport
    private let manifestVerifier: ManifestVerifier

    public init(
        transport: any DownloadTransport = URLSessionDownloadTransport(),
        manifestVerifier: ManifestVerifier
    ) {
        self.transport = transport
        self.manifestVerifier = manifestVerifier
    }

    public func downloadManifest(
        manifestURL: URL,
        signatureURL: URL
    ) async throws -> ModelManifest {
        let manifestResponse = try await transport.fetch(URLRequest(url: manifestURL))
        let signatureResponse = try await transport.fetch(URLRequest(url: signatureURL))
        return try manifestVerifier.verify(
            manifestData: manifestResponse.data,
            signatureData: signatureResponse.data
        )
    }
}
```

- [ ] **Step 4: Add production policy and storage layout**

Create `ProductionModelPolicy.swift`:

```swift
public enum ProductionModelPolicyError: Error, Equatable {
    case unsupportedManifestVersion(Int)
    case expectedSingleModel(count: Int)
    case wrongModelID(String)
    case expectedSingleFile(count: Int)
    case missingChecksum
    case invalidSize
    case languageNotEnglish
}

public enum ProductionModelPolicy {
    public static let requiredModelID = "ggml-small.en-q5_1"

    public static func validateV1_1ProductionManifest(_ manifest: ModelManifest) throws {
        guard manifest.manifestVersion == 1 else {
            throw ProductionModelPolicyError.unsupportedManifestVersion(manifest.manifestVersion)
        }
        guard manifest.models.count == 1 else {
            throw ProductionModelPolicyError.expectedSingleModel(count: manifest.models.count)
        }
        let model = manifest.models[0]
        guard model.id == requiredModelID else {
            throw ProductionModelPolicyError.wrongModelID(model.id)
        }
        guard model.files.count == 1 else {
            throw ProductionModelPolicyError.expectedSingleFile(count: model.files.count)
        }
        let file = model.files[0]
        guard !file.sha256.isEmpty else {
            throw ProductionModelPolicyError.missingChecksum
        }
        guard file.sizeBytes > 0 else {
            throw ProductionModelPolicyError.invalidSize
        }
        guard model.runtimeParameters.language == "en" else {
            throw ProductionModelPolicyError.languageNotEnglish
        }
    }
}
```

Create `ModelStorageLayout.swift` with the layout described in the grill:

```swift
import Foundation

public struct ModelStorageLayout: Equatable, Sendable {
    public let rootDirectory: URL
    public var manifestsDirectory: URL { rootDirectory.appendingPathComponent("manifests", isDirectory: true) }
    public var downloadsDirectory: URL { rootDirectory.appendingPathComponent("downloads", isDirectory: true) }
    public var installedModelsDirectory: URL { rootDirectory.appendingPathComponent("installed", isDirectory: true) }
    public var installedStoreURL: URL { rootDirectory.appendingPathComponent("installed-models.json", isDirectory: false) }

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func installedModelDirectory(modelID: String) -> URL {
        installedModelsDirectory.appendingPathComponent(modelID, isDirectory: true)
    }

    public func installedFileURL(modelID: String, filename: String) -> URL {
        installedModelDirectory(modelID: modelID).appendingPathComponent(filename, isDirectory: false)
    }

    public func temporaryDownloadURL(modelID: String, filename: String) -> URL {
        downloadsDirectory.appendingPathComponent("\(modelID)-\(filename).partial", isDirectory: false)
    }
}
```

- [ ] **Step 5: Add installer and atomic store update**

Create `ModelInstallError.swift`:

```swift
public enum ModelInstallError: Error, Equatable {
    case modelNotFound(String)
    case expectedSingleFile(count: Int)
    case invalidDownloadURL(String)
    case checksumMismatch(expected: String, actual: String)
    case filesystem(String)
}
```

Extend `DownloadTransport` with:

```swift
func downloadFile(_ request: URLRequest, to temporaryURL: URL) async throws -> DownloadFileResponse
```

Add the response type next to `DownloadResponse`:

```swift
public struct DownloadFileResponse: Equatable, Sendable {
    public let fileURL: URL
    public let eTag: String?
    public let lastModified: String?
    public let statusCode: Int?

    public init(fileURL: URL, eTag: String? = nil, lastModified: String? = nil, statusCode: Int? = nil) {
        self.fileURL = fileURL
        self.eTag = eTag
        self.lastModified = lastModified
        self.statusCode = statusCode
    }
}
```

Add this method to `URLSessionDownloadTransport`:

```swift
public func downloadFile(_ request: URLRequest, to temporaryURL: URL) async throws -> DownloadFileResponse {
    let (downloadedURL, response) = try await session.download(for: request)
    let httpResponse = response as? HTTPURLResponse
    if let statusCode = httpResponse?.statusCode,
       !(200..<300).contains(statusCode) {
        throw DownloadTransportError.unacceptableStatusCode(statusCode)
    }
    try? FileManager.default.removeItem(at: temporaryURL)
    try FileManager.default.moveItem(at: downloadedURL, to: temporaryURL)
    return DownloadFileResponse(
        fileURL: temporaryURL,
        eTag: httpResponse?.value(forHTTPHeaderField: "ETag"),
        lastModified: httpResponse?.value(forHTTPHeaderField: "Last-Modified"),
        statusCode: httpResponse?.statusCode
    )
}
```

Create `ModelInstaller.swift`:

```swift
import CryptoKit
import Foundation

public struct ModelInstaller {
    private let layout: ModelStorageLayout
    private let transport: any DownloadTransport
    private let fileManager: FileManager
    private let nowISO8601: @Sendable () -> String

    public init(
        layout: ModelStorageLayout,
        transport: any DownloadTransport,
        fileManager: FileManager = .default,
        nowISO8601: @escaping @Sendable () -> String = { ISO8601DateFormatter().string(from: Date()) }
    ) {
        self.layout = layout
        self.transport = transport
        self.fileManager = fileManager
        self.nowISO8601 = nowISO8601
    }

    public func install(modelID: String, from manifest: ModelManifest) async throws -> InstalledModelRecord {
        guard let model = manifest.models.first(where: { $0.id == modelID }) else {
            throw ModelInstallError.modelNotFound(modelID)
        }
        guard model.files.count == 1 else {
            throw ModelInstallError.expectedSingleFile(count: model.files.count)
        }
        let file = model.files[0]
        guard let url = URL(string: file.url) else {
            throw ModelInstallError.invalidDownloadURL(file.url)
        }

        try createDirectories()
        let temporaryURL = layout.temporaryDownloadURL(modelID: model.id, filename: file.filename)
        let installedURL = layout.installedFileURL(modelID: model.id, filename: file.filename)
        try? fileManager.removeItem(at: temporaryURL)

        _ = try await transport.downloadFile(URLRequest(url: url), to: temporaryURL)
        let actualChecksum = try sha256Hex(fileURL: temporaryURL)
        guard actualChecksum.lowercased() == file.sha256.lowercased() else {
            try? fileManager.removeItem(at: temporaryURL)
            throw ModelInstallError.checksumMismatch(expected: file.sha256, actual: actualChecksum)
        }

        try fileManager.createDirectory(
            at: layout.installedModelDirectory(modelID: model.id),
            withIntermediateDirectories: true
        )
        try? fileManager.removeItem(at: installedURL)
        try fileManager.moveItem(at: temporaryURL, to: installedURL)

        let record = InstalledModelRecord(
            model: model,
            installedAt: nowISO8601(),
            localFilesByManifestFilename: [file.filename: installedURL.path]
        )
        try upsertInstalledRecord(record)
        return record
    }

    private func createDirectories() throws {
        for directory in [
            layout.rootDirectory,
            layout.manifestsDirectory,
            layout.downloadsDirectory,
            layout.installedModelsDirectory
        ] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func upsertInstalledRecord(_ record: InstalledModelRecord) throws {
        var store = try loadStore()
        store.upsert(record)
        let data = try JSONEncoder().encode(store)
        try data.write(to: layout.installedStoreURL, options: [.atomic])
    }

    private func loadStore() throws -> InstalledModelsStore {
        guard fileManager.fileExists(atPath: layout.installedStoreURL.path) else {
            return InstalledModelsStore()
        }
        let data = try Data(contentsOf: layout.installedStoreURL)
        return try JSONDecoder().decode(InstalledModelsStore.self, from: data)
    }

    private func sha256Hex(fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 6: Verify tests**

```bash
swift test --filter TextifyModelsTests
swift test
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/TextifyModels Tests/TextifyModelsTests
git commit -m "v1.1: update model trust and install pipeline"
```

## Task 5: TextifyTranscription Whisper Options And Metrics

**Files:**

- Modify: `Sources/TextifyTranscription/TranscriptionResult.swift`
- Modify: `Sources/TextifyTranscription/Native/WhisperRuntime.swift`
- Modify: `Sources/TextifyTranscription/WhisperRuntimeState.swift`
- Create: `Sources/TextifyTranscription/Native/WhisperTranscriptionOptions.swift`
- Create: `Sources/TextifyTranscription/Native/WhisperRuntimeMetrics.swift`
- Modify: `Sources/TextifyWhisperShim/include/TextifyWhisperShim.h`
- Modify: `Sources/TextifyWhisperShim/TextifyWhisperShim.mm`
- Create: `Tests/TextifyTranscriptionTests/WhisperTranscriptionOptionsTests.swift`
- Modify: `Tests/TextifyTranscriptionTests/NativeWhisperBoundaryTests.swift`
- Modify: `Tests/TextifyTranscriptionTests/MockTranscriptionTests.swift`

- [ ] **Step 1: Write failing options tests**

Create `Tests/TextifyTranscriptionTests/WhisperTranscriptionOptionsTests.swift`:

```swift
import TextifyTranscription
import XCTest

final class WhisperTranscriptionOptionsTests: XCTestCase {
    func testV11EnglishOptionsPinEnglishLocalDictation() {
        let options = WhisperTranscriptionOptions.v1_1English

        XCTAssertEqual(options.language, "en")
        XCTAssertFalse(options.translate)
        XCTAssertEqual(options.temperature, 0)
        XCTAssertTrue(options.temperatureFallback.isEmpty)
        XCTAssertFalse(options.usePreviousContext)
        XCTAssertNil(options.initialPrompt)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
swift test --filter WhisperTranscriptionOptionsTests
```

Expected: fails because `WhisperTranscriptionOptions` does not exist.

- [ ] **Step 3: Add options and timing types**

Create `WhisperTranscriptionOptions.swift`:

```swift
public struct WhisperTranscriptionOptions: Equatable, Sendable {
    public let language: String
    public let translate: Bool
    public let temperature: Float
    public let temperatureFallback: [Float]
    public let usePreviousContext: Bool
    public let initialPrompt: String?

    public init(
        language: String,
        translate: Bool,
        temperature: Float,
        temperatureFallback: [Float],
        usePreviousContext: Bool,
        initialPrompt: String?
    ) {
        self.language = language
        self.translate = translate
        self.temperature = temperature
        self.temperatureFallback = temperatureFallback
        self.usePreviousContext = usePreviousContext
        self.initialPrompt = initialPrompt
    }

    public static let v1_1English = WhisperTranscriptionOptions(
        language: "en",
        translate: false,
        temperature: 0,
        temperatureFallback: [],
        usePreviousContext: false,
        initialPrompt: nil
    )
}
```

Modify `TranscriptionResult.swift`:

```swift
public struct TranscriptionTiming: Equatable, Codable, Sendable {
    public let audioDurationMs: Int
    public let inferenceDurationMs: Int

    public init(audioDurationMs: Int, inferenceDurationMs: Int) {
        self.audioDurationMs = audioDurationMs
        self.inferenceDurationMs = inferenceDurationMs
    }
}

public struct TranscriptionResult: Equatable, Codable, Sendable {
    public let text: String
    public let noSpeechProbability: Double
    public let averageLogProbability: Double
    public let compressionRatio: Double
    public let timing: TranscriptionTiming?

    public init(
        text: String,
        noSpeechProbability: Double,
        averageLogProbability: Double,
        compressionRatio: Double,
        timing: TranscriptionTiming? = nil
    ) {
        self.text = text
        self.noSpeechProbability = noSpeechProbability
        self.averageLogProbability = averageLogProbability
        self.compressionRatio = compressionRatio
        self.timing = timing
    }
}
```

- [ ] **Step 4: Add runtime metrics and snapshot**

Create `WhisperRuntimeMetrics.swift`:

```swift
public struct WhisperRuntimeMetrics: Equatable, Sendable {
    public let lastLoadDurationMs: Int?
    public let lastWarmupDurationMs: Int?
    public let lastInferenceDurationMs: Int?

    public init(lastLoadDurationMs: Int? = nil, lastWarmupDurationMs: Int? = nil, lastInferenceDurationMs: Int? = nil) {
        self.lastLoadDurationMs = lastLoadDurationMs
        self.lastWarmupDurationMs = lastWarmupDurationMs
        self.lastInferenceDurationMs = lastInferenceDurationMs
    }
}

public struct WhisperRuntimeSnapshot: Equatable, Sendable {
    public let state: WhisperRuntimeState
    public let metrics: WhisperRuntimeMetrics
}
```

Update `WhisperRuntime` to expose:

```swift
public func snapshot() -> WhisperRuntimeSnapshot
public func transcribe(_ audio: TranscriptionAudioBuffer, options: WhisperTranscriptionOptions) async throws -> TranscriptionResult
```

The existing `transcribe(_:)` must call `.v1_1English`.

- [ ] **Step 5: Update shim for explicit options**

Modify `TextifyWhisperShim.h` to pass language, translate, temperature, no-context, and prompt. Modify `TextifyWhisperShim.mm` to set:

```text
params.language = "en"
params.translate = false
params.temperature = 0
params.no_context = true
```

If `initialPrompt` is nil, pass no prompt.

- [ ] **Step 6: Verify tests and native boundary build**

```bash
swift test --filter TextifyTranscriptionTests
swift test
swift build -c release --arch arm64
```

Expected: all tests pass and release build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Sources/TextifyTranscription Sources/TextifyWhisperShim Tests/TextifyTranscriptionTests
git commit -m "v1.1: add whisper options and metrics"
```

## Task 6: TextifySettings And TextifyDiagnostics Production Persistence

**Files:**

- Modify: `Sources/TextifySettings/AppPreferences.swift`
- Modify: `Sources/TextifySettings/SettingsStore.swift`
- Create: `Sources/TextifySettings/SettingsStoreError.swift`
- Modify: `Tests/TextifySettingsTests/SettingsStoreTests.swift`
- Modify: `Sources/TextifyDiagnostics/DiagnosticEvent.swift`
- Modify: `Sources/TextifyDiagnostics/DiagnosticsLogger.swift`
- Modify: `Sources/TextifyDiagnostics/DiagnosticsExporter.swift`
- Create: `Sources/TextifyDiagnostics/DiagnosticsRetentionPolicy.swift`
- Create: `Sources/TextifyDiagnostics/DiagnosticsRedactor.swift`
- Modify: `Tests/TextifyDiagnosticsTests/DiagnosticsTests.swift`

- [ ] **Step 1: Write failing settings migration test**

Add to `Tests/TextifySettingsTests/SettingsStoreTests.swift`:

```swift
func testDecodesOldLaunchAtLoginRequestedByOnboardingIntoLaunchAtLoginEnabled() throws {
    let json = """
    {
      "trigger": "rightCommand",
      "microphoneSelection": "systemDefault",
      "transcriptionLanguage": "en",
      "modelSelectionScope": "curatedInstalledModels",
      "launchAtLoginRequestedByOnboarding": false,
      "onboardingCompleted": true
    }
    """
    let preferences = try JSONDecoder().decode(AppPreferences.self, from: Data(json.utf8))

    XCTAssertFalse(preferences.launchAtLoginEnabled)
    XCTAssertTrue(preferences.onboardingCompleted)
}
```

- [ ] **Step 2: Write failing diagnostics redaction test**

Add to `Tests/TextifyDiagnosticsTests/DiagnosticsTests.swift`:

```swift
func testDiagnosticsEventDoesNotEncodeContentFields() throws {
    let event = DiagnosticEvent.transcriptionCompleted(
        modelID: "ggml-small.en-q5_1",
        audioDurationMs: 5_000,
        inferenceDurationMs: 1_500,
        textLengthBucket: "1-50"
    )
    let data = try JSONEncoder().encode(event)
    let json = String(decoding: data, as: UTF8.self)

    XCTAssertFalse(json.localizedCaseInsensitiveContains("transcript"))
    XCTAssertFalse(json.localizedCaseInsensitiveContains("clipboard"))
    XCTAssertFalse(json.localizedCaseInsensitiveContains("audioSamples"))
}
```

- [ ] **Step 3: Run tests to verify failure**

```bash
swift test --filter TextifySettingsTests
swift test --filter TextifyDiagnosticsTests
```

Expected: fails because `launchAtLoginEnabled` and new redacted diagnostic events do not exist.

- [ ] **Step 4: Update preferences**

Modify `AppPreferences`:

- Add `launchAtLoginEnabled`.
- Keep `automaticallyCheckForUpdates` persisted but no Release UI while Sparkle is deferred.
- Remove persisted user-visible history concepts.
- Decode old `launchAtLoginRequestedByOnboarding` into `launchAtLoginEnabled`.

Use this field and coding-key change:

```swift
public var launchAtLoginEnabled: Bool

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
```

In `init(from:)`, decode the new key first and fall back to the old key:

```swift
let launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLoginEnabled)
    ?? container.decodeIfPresent(Bool.self, forKey: .launchAtLoginRequestedByOnboarding)
    ?? defaults.launchAtLoginEnabled
```

The V1.1 initializer default is `launchAtLoginEnabled: true`. Remove `developerModeEnabled` from Release preferences; debug-only state must not persist in `settings.json`.

- [ ] **Step 5: Add diagnostics retention and export**

Create `DiagnosticsRetentionPolicy.swift`:

```swift
public struct DiagnosticsRetentionPolicy: Equatable, Sendable {
    public let maxAgeDays: Int
    public let maxFileCount: Int
    public let maxTotalBytes: Int64

    public init(maxAgeDays: Int, maxFileCount: Int, maxTotalBytes: Int64) {
        self.maxAgeDays = maxAgeDays
        self.maxFileCount = maxFileCount
        self.maxTotalBytes = maxTotalBytes
    }

    public static let v1_1Default = DiagnosticsRetentionPolicy(
        maxAgeDays: 14,
        maxFileCount: 20,
        maxTotalBytes: 10 * 1_024 * 1_024
    )
}
```

Modify `DiagnosticsLogger` to add retention operations:

```swift
public func rotate(policy: DiagnosticsRetentionPolicy = .v1_1Default, now: Date = Date()) throws {
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let files = try diagnosticLogFiles()
    let cutoff = Calendar.current.date(byAdding: .day, value: -policy.maxAgeDays, to: now) ?? now
    for file in files where file.modifiedAt < cutoff {
        try? fileManager.removeItem(at: file.url)
    }
    let remaining = try diagnosticLogFiles().sorted { $0.modifiedAt > $1.modifiedAt }
    for file in remaining.dropFirst(policy.maxFileCount) {
        try? fileManager.removeItem(at: file.url)
    }
    var totalBytes = try diagnosticLogFiles().reduce(Int64(0)) { $0 + $1.sizeBytes }
    for file in try diagnosticLogFiles().sorted(by: { $0.modifiedAt < $1.modifiedAt }) where totalBytes > policy.maxTotalBytes {
        try? fileManager.removeItem(at: file.url)
        totalBytes -= file.sizeBytes
    }
}

public func clear() throws {
    for file in try diagnosticLogFiles() {
        try? fileManager.removeItem(at: file.url)
    }
}

private func diagnosticLogFiles() throws -> [DiagnosticLogFile] {
    guard fileManager.fileExists(atPath: directory.path) else { return [] }
    return try fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
        options: [.skipsHiddenFiles]
    )
    .filter { $0.lastPathComponent.hasPrefix("diagnostics-") || $0.lastPathComponent.hasPrefix("log-") }
    .filter { $0.pathExtension == "jsonl" }
    .map { url in
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return DiagnosticLogFile(
            url: url,
            modifiedAt: values.contentModificationDate ?? .distantPast,
            sizeBytes: Int64(values.fileSize ?? 0)
        )
    }
}

private struct DiagnosticLogFile {
    let url: URL
    let modifiedAt: Date
    let sizeBytes: Int64
}
```

Modify `DiagnosticsExporter` to export only log files under the diagnostics directory:

```swift
public struct DiagnosticsExportDocument: Equatable, Sendable {
    public let formatVersion: Int
    public let files: [DiagnosticsExportFile]
}

public struct DiagnosticsExportFile: Equatable, Sendable {
    public let filename: String
    public let contents: String
}

public func exportRedactedLogs(from directory: URL, fileManager: FileManager = .default) throws -> DiagnosticsExportDocument {
    guard fileManager.fileExists(atPath: directory.path) else {
        return DiagnosticsExportDocument(formatVersion: 1, files: [])
    }
    let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "jsonl" }
        .filter { $0.lastPathComponent.hasPrefix("diagnostics-") || $0.lastPathComponent.hasPrefix("log-") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    let files = try urls.map { url in
        DiagnosticsExportFile(
            filename: url.lastPathComponent,
            contents: try String(contentsOf: url, encoding: .utf8)
        )
    }
    return DiagnosticsExportDocument(formatVersion: 1, files: files)
}
```

- [ ] **Step 6: Verify tests**

```bash
swift test --filter TextifySettingsTests
swift test --filter TextifyDiagnosticsTests
swift test
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/TextifySettings Tests/TextifySettingsTests Sources/TextifyDiagnostics Tests/TextifyDiagnosticsTests
git commit -m "v1.1: add production settings and diagnostics"
```

## Task 7: TextifyRuntime Adapters And Readiness

**Files:**

- Create: `Sources/TextifyRuntime/Adapters/RuntimeSettingsStoreAdapter.swift`
- Create: `Sources/TextifyRuntime/Adapters/RuntimeDiagnosticsLoggerAdapter.swift`
- Create: `Sources/TextifyRuntime/Adapters/RuntimeAudioRecorderAdapter.swift`
- Create: `Sources/TextifyRuntime/Adapters/WhisperRuntimeTranscribingAdapter.swift`
- Create: `Sources/TextifyRuntime/Adapters/RuntimePostProcessingAdapter.swift`
- Create: `Sources/TextifyRuntime/Adapters/RuntimeModelResolverAdapter.swift`
- Create: `Sources/TextifyRuntime/Adapters/SystemRuntimeClock.swift`
- Modify: `Sources/TextifyRuntime/Readiness/ReadinessSnapshot.swift`
- Create: `Tests/TextifyRuntimeTests/RuntimeAdaptersTests.swift`
- Create: `Tests/TextifyRuntimeTests/ReadinessTests.swift`

- [ ] **Step 1: Write failing adapter tests**

Create `Tests/TextifyRuntimeTests/RuntimeAdaptersTests.swift`:

```swift
import TextifyRuntime
import TextifySettings
import XCTest

final class RuntimeAdaptersTests: XCTestCase {
    func testSettingsAdapterLoadsPreferences() async {
        let store = SettingsStore(storage: .memory)
        var preferences = AppPreferences.defaults
        preferences.activeModelID = "ggml-small.en-q5_1"
        store.save(preferences)
        let adapter = RuntimeSettingsStoreAdapter(store: store)

        let loaded = await adapter.loadPreferences()

        XCTAssertEqual(loaded.activeModelID, "ggml-small.en-q5_1")
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
swift test --filter RuntimeAdaptersTests
```

Expected: fails because runtime adapters do not exist.

- [ ] **Step 3: Add settings and diagnostics adapters**

Create `RuntimeSettingsStoreAdapter.swift`:

```swift
import TextifySettings

public actor RuntimeSettingsStoreAdapter: RuntimeSettingsProviding {
    private let store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
    }

    public func loadPreferences() async -> AppPreferences {
        store.load()
    }

    public func savePreferences(_ preferences: AppPreferences) async {
        store.save(preferences)
    }
}
```

Create `RuntimeDiagnosticsLoggerAdapter.swift`:

```swift
import TextifyDiagnostics

public actor RuntimeDiagnosticsLoggerAdapter: RuntimeDiagnosticsLogging {
    private let logger: DiagnosticsLogger

    public init(logger: DiagnosticsLogger) {
        self.logger = logger
    }

    public func log(_ event: DiagnosticEvent) async {
        try? await logger.log(event)
    }
}
```

- [ ] **Step 4: Add audio, transcription, model, and post-processing adapters**

Create `RuntimeAudioRecorderAdapter.swift`:

```swift
import TextifyAudio
import TextifySettings
import TextifyTranscription

public actor RuntimeAudioRecorderAdapter: RuntimeAudioRecording {
    private let recorder: LiveAudioRecorder

    public init(recorder: LiveAudioRecorder = LiveAudioRecorder()) {
        self.recorder = recorder
    }

    public func startRecording(
        microphone: MicrophoneSelection,
        onSpeechDetected: @escaping @Sendable () -> Void
    ) async throws {
        guard microphone == .systemDefault else {
            throw LiveAudioRecorderError.unsupportedInput
        }
        try await recorder.startRecording(
            onSpeechDetected: onSpeechDetected,
            onMaximumDurationReached: {}
        )
    }

    public func finishRecording() async throws -> CanonicalAudioBuffer {
        try await recorder.finishRecording()
    }

    public func discardRecording() async {
        await recorder.discardRecording()
    }
}
```

Create `WhisperRuntimeTranscribingAdapter.swift`:

```swift
import TextifyTranscription

public actor WhisperRuntimeTranscribingAdapter: RuntimeTranscribing {
    private let runtime: WhisperRuntime

    public init(runtime: WhisperRuntime) {
        self.runtime = runtime
    }

    public var readiness: RuntimeModelReadiness {
        get async {
            await Self.map(state: runtime.state)
        }
    }

    public func prepare(model: RuntimeActiveModel) async throws {
        let state = await runtime.state
        if case let .ready(modelID) = state, modelID == model.id {
            return
        }
        try await runtime.load(
            modelID: model.id,
            modelPath: model.localModelPath,
            useGPU: model.useGPU,
            threadCount: model.threadCount ?? ProcessInfo.processInfo.activeProcessorCount,
            warmup: true
        )
    }

    public func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult {
        try await runtime.transcribe(audio, options: .v1_1English)
    }

    private static func map(state: WhisperRuntimeState) -> RuntimeModelReadiness {
        switch state {
        case .noModel:
            return .noActiveModel
        case let .loading(modelID):
            return .loading(modelID: modelID)
        case let .preparing(modelID):
            return .warming(modelID: modelID)
        case let .ready(modelID):
            return .ready(modelID: modelID)
        case let .unloadedToSaveMemory(modelID):
            return .loading(modelID: modelID)
        case let .failed(modelID, reason):
            return .failed(modelID: modelID, reason: mapFailure(reason))
        }
    }

    private static func mapFailure(_ failure: WhisperRuntimeFailure) -> RuntimeModelFailure {
        switch failure {
        case .missingModelFile: return .missingFile
        case .checksumFailure: return .checksumFailed
        case .loadFailed, .memoryFailure: return .loadFailed
        case .warmupFailed: return .warmupFailed
        }
    }
}
```

Create `RuntimeModelResolverAdapter.swift`:

```swift
import CryptoKit
import Foundation
import TextifyModels
import TextifySettings

public actor RuntimeModelResolverAdapter: RuntimeModelResolving {
    private let layout: ModelStorageLayout
    private let loadStore: @Sendable () throws -> InstalledModelsStore

    public init(
        layout: ModelStorageLayout,
        loadStore: @escaping @Sendable () throws -> InstalledModelsStore
    ) {
        self.layout = layout
        self.loadStore = loadStore
    }

    public func resolveActiveModel(preferences: AppPreferences) async -> RuntimeActiveModel? {
        guard preferences.modelSelectionScope == .curatedInstalledModels,
              let modelID = preferences.activeModelID,
              let record = try? loadStore().record(forModelID: modelID),
              let firstFile = record.model.files.first,
              let canonicalURL = try? layout.installedFileURL(
                  modelID: record.model.id,
                  filename: firstFile.filename
              ),
              record.localFilesByManifestFilename[firstFile.filename] == canonicalURL.path else {
            return nil
        }
        return RuntimeActiveModel(
            id: record.model.id,
            displayName: record.model.displayName,
            tier: record.model.tier,
            localModelPath: canonicalURL.path,
            useGPU: true,
            threadCount: ProcessInfo.processInfo.activeProcessorCount
        )
    }

    public func readiness(for activeModel: RuntimeActiveModel?) async -> RuntimeModelReadiness {
        guard let activeModel else { return .noActiveModel }
        guard let record = try? loadStore().record(forModelID: activeModel.id),
              let firstFile = record.model.files.first,
              let canonicalURL = try? layout.installedFileURL(
                  modelID: record.model.id,
                  filename: firstFile.filename
              ),
              record.localFilesByManifestFilename[firstFile.filename] == canonicalURL.path else {
            return .missing(modelID: activeModel.id)
        }
        guard FileManager.default.fileExists(atPath: canonicalURL.path) else {
            return .missing(modelID: activeModel.id)
        }
        guard canonicalURL.path == activeModel.localModelPath,
              fileSize(at: canonicalURL) == firstFile.sizeBytes,
              (try? Self.sha256Hex(fileURL: canonicalURL)) == firstFile.sha256 else {
            return .failed(modelID: activeModel.id, reason: .checksumFailed)
        }
        return .ready(modelID: activeModel.id)
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let fileSize = try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? NSNumber else {
            return nil
        }
        return fileSize.int64Value
    }

    private static func sha256Hex(fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
```

Create `RuntimePostProcessingAdapter.swift`:

```swift
import TextifyCore
import TextifySettings

public struct RuntimePostProcessingAdapter: RuntimePostProcessing {
    public init() {}

    public func process(rawText: String, preferences: AppPreferences) async -> String {
        PostProcessingPipeline().process(rawText: rawText, replacements: [])
    }
}
```

Create `SystemRuntimeClock.swift`:

```swift
import Foundation

public struct SystemRuntimeClock: RuntimeClock {
    public init() {}

    public func nowMilliseconds() -> Int {
        Int(Date().timeIntervalSince1970 * 1_000)
    }

    public func sleep(milliseconds: Int) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, milliseconds)) * 1_000_000)
    }
}
```

Add a `RuntimePermissionChecking` adapter in `TextifyRuntime` after the three domain clients exist:

```swift
import TextifyAudio
import TextifyHotkeys
import TextifyInsertion

public struct SystemRuntimePermissionAdapter: RuntimePermissionChecking {
    private let microphone: MicrophonePermissionClient
    private let inputMonitoring: InputMonitoringPermissionClient
    private let accessibility: AccessibilityTrustClient

    public init(
        microphone: MicrophonePermissionClient = .live,
        inputMonitoring: InputMonitoringPermissionClient = .live,
        accessibility: AccessibilityTrustClient
    ) {
        self.microphone = microphone
        self.inputMonitoring = inputMonitoring
        self.accessibility = accessibility
    }

    public func permissionSnapshot() async -> RuntimePermissionSnapshot {
        RuntimePermissionSnapshot(
            microphone: microphone.status() == .granted ? .granted : .denied,
            accessibility: accessibility.status() == .trusted ? .granted : .denied,
            inputMonitoring: inputMonitoring.status() == .granted ? .granted : .unknown
        )
    }
}
```

- [ ] **Step 5: Verify tests**

```bash
swift test --filter TextifyRuntimeTests
swift test
```

Expected: all tests pass.

- [ ] **Step 6: Verify dependency direction**

```bash
rg -n "import TextifyRuntime" Sources/TextifyAudio Sources/TextifyCore Sources/TextifyDiagnostics Sources/TextifyHotkeys Sources/TextifyInsertion Sources/TextifyModels Sources/TextifySettings Sources/TextifyTranscription
```

Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add Sources/TextifyRuntime Tests/TextifyRuntimeTests
git commit -m "v1.1: add runtime adapters"
```

## Task 8: AppDictationService Production Orchestration

**Files:**

- Modify: `Sources/TextifyRuntime/Dictation/AppDictationService.swift`
- Modify: `Sources/TextifyRuntime/Dictation/DictationRuntimeStatus.swift`
- Modify: `Sources/TextifyRuntime/Dictation/ProductionDictationError.swift`
- Create: `Tests/TextifyRuntimeTests/AppDictationServiceTests.swift`

- [ ] **Step 1: Write failing orchestration tests**

Create `Tests/TextifyRuntimeTests/AppDictationServiceTests.swift` with fake dependencies. Include these tests:

```swift
@MainActor
func testBeginRecordingRefreshesReadinessBeforeStartingAudio() async {
    let fakes = RuntimeFakes.ready()
    let service = AppDictationService(dependencies: fakes.dependencies)

    await service.handleTriggerAction(.beginRecording)

    XCTAssertEqual(fakes.permissions.snapshotCount, 1)
    XCTAssertEqual(fakes.audio.startCount, 1)
    XCTAssertEqual(service.status, .recording(speechDetected: false))
}

@MainActor
func testReadinessBlockerPreventsAudioStart() async {
    let fakes = RuntimeFakes.blocked(blocker: .microphonePermissionDenied)
    let service = AppDictationService(dependencies: fakes.dependencies)

    await service.handleTriggerAction(.beginRecording)

    XCTAssertEqual(fakes.audio.startCount, 0)
    XCTAssertEqual(service.status, .blocked(.readinessBlocked(.microphonePermissionDenied)))
}

@MainActor
func testCancellationDuringTranscriptionPreventsLateInsertion() async {
    let fakes = RuntimeFakes.ready(transcript: "late text")
    fakes.transcriber.suspendUntilReleased = true
    let service = AppDictationService(dependencies: fakes.dependencies)

    await service.handleTriggerAction(.beginRecording)
    let task = Task { await service.handleTriggerAction(.finishRecording) }
    await service.cancelActiveSession(reason: .escapeKey)
    fakes.transcriber.release()
    await task.value

    XCTAssertEqual(fakes.inserter.insertedTexts.count, 0)
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
swift test --filter AppDictationServiceTests
```

Expected: fails because orchestration is still a shell.

- [ ] **Step 3: Implement production state flow**

Add these imports at the top of `AppDictationService.swift`:

```swift
import Foundation
import TextifyAudio
import TextifyInsertion
import TextifyTranscription
```

Add session-token state inside `AppDictationService`:

```swift
private var activationTimerToken: UUID?
private var activeSessionID: UUID?
```

Replace `handleTriggerAction(_:)` with:

```swift
public func handleTriggerAction(_ action: TriggerAction) async {
    switch action {
    case .none:
        return
    case let .startActivationTimer(delayMs):
        startActivationTimer(delayMs: delayMs)
    case .beginRecording:
        await beginRecording()
    case .cancelAsShortcut:
        await cancelActiveSession(reason: .shortcutUseBeforeSpeech)
    case .cancelRecording:
        await cancelActiveSession(reason: .escapeKey)
    case .discardRecording:
        await dependencies.audio.discardRecording()
        activeSessionID = nil
        status = .cancelled(.noSpeechDetected)
    case .finishRecording:
        await finishRecording()
    }
}
```

Add activation timing:

```swift
private func startActivationTimer(delayMs: Int) {
    let token = UUID()
    activationTimerToken = token
    status = .waitingForActivation
    Task { @MainActor [weak self] in
        guard let self else { return }
        await self.dependencies.clock.sleep(milliseconds: delayMs)
        guard self.activationTimerToken == token else { return }
        _ = await self.handleTriggerEvent(.timerFired(timestampMs: self.dependencies.clock.nowMilliseconds()))
    }
}
```

Add recording start:

```swift
private func beginRecording() async {
    let snapshot = await refreshReadiness()
    if let blocker = snapshot.blockers.first {
        status = .blocked(.readinessBlocked(blocker))
        return
    }
    let preferences = await dependencies.settings.loadPreferences()
    let sessionID = UUID()
    activeSessionID = sessionID
    do {
        try await dependencies.audio.startRecording(microphone: preferences.microphoneSelection) { [weak self] in
            Task { @MainActor in
                guard let self, self.activeSessionID == sessionID else { return }
                _ = await self.handleTriggerEvent(.speechDetected(timestampMs: self.dependencies.clock.nowMilliseconds()))
            }
        }
        guard activeSessionID == sessionID else { return }
        status = .recording(speechDetected: false)
    } catch {
        activeSessionID = nil
        status = .failed(.audioStartFailed)
    }
}
```

Add finish/process/insert:

```swift
private func finishRecording() async {
    guard let sessionID = activeSessionID else {
        status = .idle
        return
    }
    status = .processing
    do {
        let audio = try await dependencies.audio.finishRecording()
        guard activeSessionID == sessionID else { return }
        guard !audio.isEmpty else {
            activeSessionID = nil
            status = .cancelled(.noSpeechDetected)
            return
        }

        let preferences = await dependencies.settings.loadPreferences()
        guard let activeModel = await dependencies.models.resolveActiveModel(preferences: preferences) else {
            activeSessionID = nil
            status = .blocked(.readinessBlocked(.noActiveModel))
            return
        }

        try await dependencies.transcriber.prepare(model: activeModel)
        guard activeSessionID == sessionID else { return }

        let transcriptionAudio = TranscriptionAudioBuffer(
            sampleRate: audio.sampleRate,
            channelCount: audio.channelCount,
            samples: audio.samples
        )
        let result = try await dependencies.transcriber.transcribe(transcriptionAudio)
        guard activeSessionID == sessionID else { return }

        let processed = await dependencies.postProcessor
            .process(rawText: result.text, preferences: preferences)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !processed.isEmpty else {
            activeSessionID = nil
            status = .idle
            return
        }

        status = .inserting
        let outcome = await dependencies.inserter.insert(InsertionRequest(text: processed))
        guard activeSessionID == sessionID else { return }
        activeSessionID = nil

        switch outcome {
        case .pasted(_):
            status = .completed(textLengthBucket: Self.textLengthBucket(for: processed.count))
        case .notInserted(_):
            status = .failed(.insertionFailed)
        }
    } catch let error as LiveAudioRecorderError {
        activeSessionID = nil
        status = error == .emptyRecording ? .cancelled(.noSpeechDetected) : .failed(.audioFinishFailed)
    } catch is WhisperRuntimeError {
        activeSessionID = nil
        status = .failed(.transcriptionFailed)
    } catch {
        activeSessionID = nil
        status = .failed(.transcriptionFailed)
    }
}
```

Update cancellation:

```swift
public func cancelActiveSession(reason: DictationCancellationReason) async {
    activationTimerToken = nil
    activeSessionID = nil
    await dependencies.audio.discardRecording()
    status = .cancelled(reason)
}
```

Add the redacted text length helper:

```swift
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
```

- [ ] **Step 4: Verify focused and full tests**

```bash
swift test --filter TextifyRuntimeTests
swift test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TextifyRuntime Tests/TextifyRuntimeTests
git commit -m "v1.1: add production dictation orchestration"
```

## Task 9: Textify App Composition And Launch At Login

**Files:**

- Modify: `Sources/Textify/App/TextifyApp.swift`
- Modify: `Sources/Textify/App/AppDelegate.swift`
- Rewrite: `Sources/Textify/App/AppServices.swift`
- Create: `Sources/Textify/App/AppPaths.swift`
- Create: `Sources/Textify/App/LaunchAtLoginController.swift`
- Modify: `Tests/Textify*` only if app tests are already supported

- [ ] **Step 1: Write compile-level composition test if supported**

If the executable target can be imported by tests, create `Tests/TextifyAppTests/AppServicesCompositionTests.swift`:

```swift
@testable import Textify
import XCTest

@MainActor
final class AppServicesCompositionTests: XCTestCase {
    func testProductionServicesCreatesDictationService() {
        let services = AppServices.production()
        XCTAssertNotNil(services.dictation)
    }
}
```

If executable target import is not supported in the current SwiftPM layout, record that in `docs/implementation/coordination.md` and verify with `swift build`.

- [ ] **Step 2: Add AppPaths**

Create `AppPaths.swift`:

```swift
import Foundation

struct AppPaths {
    let applicationSupportDirectory: URL
    let settingsFileURL: URL
    let modelsDirectory: URL
    let logsDirectory: URL

    static func production(fileManager: FileManager = .default) throws -> AppPaths {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Textify", isDirectory: true)
        let logs = try fileManager.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Logs/Textify", isDirectory: true)
        return AppPaths(
            applicationSupportDirectory: appSupport,
            settingsFileURL: appSupport.appendingPathComponent("settings.json", isDirectory: false),
            modelsDirectory: appSupport.appendingPathComponent("Models", isDirectory: true),
            logsDirectory: logs
        )
    }
}
```

- [ ] **Step 3: Add Launch At Login controller**

Create `LaunchAtLoginController.swift`:

```swift
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
    case failed(String)
}

protocol LaunchAtLoginManaging {
    func status() -> LaunchAtLoginStatus
    func setEnabled(_ enabled: Bool) async -> LaunchAtLoginStatus
}

struct LaunchAtLoginController: LaunchAtLoginManaging {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    func status() -> LaunchAtLoginStatus {
        switch service.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        @unknown default:
            return .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) async -> LaunchAtLoginStatus {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            return status()
        } catch {
            return .failed(String(describing: error))
        }
    }
}
```

- [ ] **Step 4: Rewrite AppServices as composition facade**

Replace the current mock-heavy `AppServices` body with this production shape:

```swift
import Foundation
import Observation
import TextifyAudio
import TextifyDiagnostics
import TextifyHotkeys
import TextifyInsertion
import TextifyModels
import TextifyRuntime
import TextifySettings
import TextifyTranscription

@MainActor
@Observable
final class AppServices {
    let settingsRouter = SettingsRouter()
    let paths: AppPaths
    let settingsStore: SettingsStore
    let diagnosticsLogger: DiagnosticsLogger
    let dictation: AppDictationService
    let hotkeyMonitor: GlobalHotkeyMonitor
    let launchAtLogin: any LaunchAtLoginManaging

    var preferences: AppPreferences
    var onboardingStep = OnboardingStep.welcome
    var overlayState = RecordingOverlayState.hidden

    static func production() -> AppServices {
        let paths = try! AppPaths.production()
        let settingsStore = SettingsStore(storage: .file(paths.settingsFileURL))
        let diagnosticsLogger = DiagnosticsLogger(directory: paths.logsDirectory)
        let modelLayout = ModelStorageLayout(rootDirectory: paths.modelsDirectory)
        let whisperRuntime = WhisperRuntime()
        let dependencies = RuntimeDependencies(
            settings: RuntimeSettingsStoreAdapter(store: settingsStore),
            permissions: SystemRuntimePermissionAdapter(accessibility: .live),
            models: RuntimeModelResolverAdapter(
                layout: modelLayout,
                loadStore: {
                    let url = modelLayout.installedStoreURL
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        return InstalledModelsStore()
                    }
                    let data = try Data(contentsOf: url)
                    return try JSONDecoder().decode(InstalledModelsStore.self, from: data)
                }
            ),
            audio: RuntimeAudioRecorderAdapter(),
            transcriber: WhisperRuntimeTranscribingAdapter(runtime: whisperRuntime),
            inserter: PasteInsertionService(
                pasteboard: SystemPasteboardClient(),
                eventPoster: SystemEventPoster(),
                accessibility: .live,
                targetChecker: SystemInsertionTargetChecker()
            ),
            diagnostics: RuntimeDiagnosticsLoggerAdapter(logger: diagnosticsLogger),
            postProcessor: RuntimePostProcessingAdapter(),
            clock: SystemRuntimeClock()
        )
        return AppServices(
            paths: paths,
            settingsStore: settingsStore,
            diagnosticsLogger: diagnosticsLogger,
            dictation: AppDictationService(dependencies: dependencies),
            hotkeyMonitor: GlobalHotkeyMonitor(),
            launchAtLogin: LaunchAtLoginController()
        )
    }

    init(
        paths: AppPaths,
        settingsStore: SettingsStore,
        diagnosticsLogger: DiagnosticsLogger,
        dictation: AppDictationService,
        hotkeyMonitor: GlobalHotkeyMonitor,
        launchAtLogin: any LaunchAtLoginManaging
    ) {
        self.paths = paths
        self.settingsStore = settingsStore
        self.diagnosticsLogger = diagnosticsLogger
        self.dictation = dictation
        self.hotkeyMonitor = hotkeyMonitor
        self.launchAtLogin = launchAtLogin
        self.preferences = settingsStore.load()
    }

    func startRuntime() {
        hotkeyMonitor.start(
            onEvent: { [weak dictation] event in
                Task { @MainActor in
                    _ = await dictation?.handleTriggerEvent(event)
                }
            },
            onFailure: { [weak dictation] _ in
                Task { @MainActor in
                    _ = await dictation?.refreshReadiness()
                }
            }
        )
    }

    func savePreferences() {
        settingsStore.save(preferences)
    }
}
```

Delete Release-owned stored properties for `MockTranscriptionProvider`, `FakeDictationInsertion`, `DictationController`, mock model catalog with base/medium entries, and transcript strings. Keep optional debug fake construction inside `#if DEBUG` in a separate extension if local debugging still needs it.

- [ ] **Step 5: Wire hotkey monitor lifecycle**

In `AppServices.startRuntime()`:

```swift
hotkeyMonitor.start(
    onEvent: { [weak dictation] event in
        Task { @MainActor in
            _ = await dictation?.handleTriggerEvent(event)
        }
    },
    onFailure: { [weak dictation] _ in
        Task { @MainActor in
            _ = await dictation?.refreshReadiness()
        }
    }
)
```

- [ ] **Step 6: Verify build**

```bash
swift test
swift build
```

Expected: all tests pass and app target builds.

- [ ] **Step 7: Commit**

```bash
git add Sources/Textify/App Tests docs/implementation/coordination.md
git commit -m "v1.1: compose production app services"
```

## Task 10: Production Menu, Onboarding, Settings, And Overlay UI

**Files:**

- Modify: `Sources/Textify/UI/MenuBarRoot.swift`
- Modify: `Sources/Textify/Onboarding/OnboardingRootView.swift`
- Modify: `Sources/Textify/SettingsUI/SettingsRootView.swift`
- Modify/Create: `Sources/Textify/Overlay/RecordingOverlayWindow.swift`
- Create: `Sources/Textify/Debug/DebugMenu.swift` only if debug-only fake actions are still needed

- [ ] **Step 1: Remove Release mock surfaces**

Remove Release-visible UI strings and controls for:

- `Run Mock Dictation`
- `Mock dictation`
- fake model catalog with base/medium entries
- disabled Sparkle update controls
- developer mode toggle
- visible history, transcript, audio, clipboard inspection

If debug actions remain, isolate them under:

```swift
#if DEBUG
...
#endif
```

- [ ] **Step 2: Update MenuBarRoot**

Menu must show:

- readiness/status line
- blocker summary
- `Settings...`
- `Finish Setup...` when onboarding incomplete or blockers exist
- `Quit Textify`

Menu must not show transcript text.

Use this replacement structure:

```swift
import AppKit
import SwiftUI

struct MenuBarRoot: View {
    @Environment(AppServices.self) private var services
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusTitle)
            .foregroundStyle(.secondary)

        if let blockerTitle {
            Text(blockerTitle)
                .foregroundStyle(.secondary)
        }

        Divider()

        Button("Settings...") {
            services.settingsRouter.selectedPane = .general
            openSettings()
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: [.command])

        if !services.preferences.onboardingCompleted || !services.dictation.readiness.canDictate {
            Button("Finish Setup...") {
                openWindow(id: "onboarding")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }

        Button("About Textify") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.orderFrontStandardAboutPanel(
                options: [.applicationName: "Textify"]
            )
        }

        Divider()

        Button("Quit Textify") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }

    private var statusTitle: String {
        switch services.dictation.status {
        case .idle: return "Ready"
        case .waitingForActivation: return "Waiting"
        case .recording: return "Recording"
        case .processing: return "Processing"
        case .inserting: return "Typing"
        case .completed: return "Done"
        case .cancelled: return "Cancelled"
        case .blocked: return "Setup Required"
        case .failed: return "Unavailable"
        }
    }

    private var blockerTitle: String? {
        services.dictation.readiness.blockers.first.map { String(describing: $0) }
    }
}
```

- [ ] **Step 3: Update OnboardingRootView**

Implement screens:

1. Welcome
2. Model install/verify for `ggml-small.en-q5_1`
3. Microphone permission
4. Accessibility permission
5. Input Monitoring permission
6. Right Command trigger test using `GlobalHotkeyMonitor` event path
7. Completion with Launch at Login checked by default

Onboarding completion persists only when the user presses Done.

Use this production step model:

```swift
enum OnboardingStep: String, CaseIterable, Identifiable {
    case welcome
    case model
    case microphone
    case accessibility
    case inputMonitoring
    case triggerTest
    case completion

    var id: Self { self }
}
```

Use this completion behavior in `OnboardingRootView`:

```swift
private func completeOnboarding() async {
    services.preferences.launchAtLoginEnabled = launchAtLogin
    services.preferences.onboardingCompleted = true
    services.savePreferences()
    _ = await services.launchAtLogin.setEnabled(launchAtLogin)
    _ = await services.dictation.refreshReadiness()
}
```

The model step must call the production `ModelDownloader` and `ModelInstaller`. The trigger-test step must use `TriggerTestSession` fed by `GlobalHotkeyMonitor`; it must not have a fake success button in Release.

- [ ] **Step 4: Update SettingsRootView**

Use these panes:

- General: Launch at Login, app version, no Sparkle controls in Release.
- Dictation: Right Command display, System Default mic display, trigger test.
- Models: one V1.1 curated model entry and install/verify state.
- Privacy: Microphone, Accessibility, Input Monitoring status and actions.
- Advanced: diagnostics export/clear and redacted runtime timings, no transcript content.

Use this pane set; remove `.vocabulary` and every Release-visible mock/developer pane:

```swift
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case dictation
    case models
    case privacy
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "General"
        case .dictation: return "Dictation"
        case .models: return "Models"
        case .privacy: return "Privacy"
        case .advanced: return "Advanced"
        }
    }
}
```

`GeneralSettingsPane` must bind to `preferences.launchAtLoginEnabled`. `ModelsSettingsPane` must show only `ggml-small.en-q5_1`. `AdvancedSettingsPane` may show timing metrics and diagnostics buttons, but must not show raw transcript, raw audio, clipboard contents, mock dictation status, or developer mode.

- [ ] **Step 5: Verify Release UI strings**

Run:

```bash
swift build -c release --arch arm64
rg -n "Mock|mock|Fake|fake|Developer Mode|Sparkle|Check for Updates|history|transcript" Sources/Textify
```

Expected: no Release-visible mock/fake/developer/Sparkle/history strings. Debug-only strings are acceptable only in files wrapped by `#if DEBUG`.

- [ ] **Step 6: Verify app build**

```bash
swift test
./script/build_and_run.sh --verify
```

Expected: tests pass and staged app launches.

- [ ] **Step 7: Commit**

```bash
git add Sources/Textify/UI Sources/Textify/Onboarding Sources/Textify/SettingsUI Sources/Textify/Overlay Sources/Textify/Debug
git commit -m "v1.1: replace mock UI with production setup"
```

## Task 11: Release Packaging Scripts And Bundle Validation

**Files:**

- Modify: `project.yml`
- Modify: `Textify.entitlements`
- Modify: `Resources/Info.plist`
- Verify: `Resources/Assets.xcassets/`
- Create: `script/release/common.sh`
- Create: `script/release/build_archive.sh`
- Create: `script/release/export_developer_id.sh`
- Create: `script/release/make_dmg.sh`
- Create: `script/release/notarize_dmg.sh`
- Create: `script/release/validate_release.sh`
- Create: `script/release/ExportOptions.DeveloperID.plist`

- [ ] **Step 1: Add release script skeletons**

Every script must start with:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

`build_archive.sh` must require:

```bash
: "${TEXTIFY_DEVELOPMENT_TEAM:?Set TEXTIFY_DEVELOPMENT_TEAM}"
: "${TEXTIFY_SIGNING_IDENTITY:?Set TEXTIFY_SIGNING_IDENTITY}"
```

`notarize_dmg.sh` must require:

```bash
: "${TEXTIFY_NOTARY_PROFILE:?Set TEXTIFY_NOTARY_PROFILE}"
```

Scripts must exit with a clear message when credentials are absent.

Create `script/release/common.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$REPO_ROOT/build/release"
ARCHIVE_PATH="$BUILD_DIR/Textify.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/Textify.app"

ensure_xcode_project() {
  cd "$REPO_ROOT"
  if [[ ! -d Textify.xcodeproj ]]; then
    xcodegen generate
  fi
}
```

Create `script/release/build_archive.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${TEXTIFY_DEVELOPMENT_TEAM:?Set TEXTIFY_DEVELOPMENT_TEAM}"
: "${TEXTIFY_SIGNING_IDENTITY:?Set TEXTIFY_SIGNING_IDENTITY}"

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
ensure_xcode_project
mkdir -p "$BUILD_DIR"

xcodebuild archive \
  -project "$REPO_ROOT/Textify.xcodeproj" \
  -scheme Textify \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEXTIFY_DEVELOPMENT_TEAM" \
  CODE_SIGN_IDENTITY="$TEXTIFY_SIGNING_IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO
```

Create `script/release/export_developer_id.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${TEXTIFY_DEVELOPMENT_TEAM:?Set TEXTIFY_DEVELOPMENT_TEAM}"

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
rm -rf "$EXPORT_PATH"
mkdir -p "$EXPORT_PATH"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$REPO_ROOT/script/release/ExportOptions.DeveloperID.plist"
```

Create `script/release/make_dmg.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-1.1.0}"
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DMG_PATH="$BUILD_DIR/Textify-$VERSION-arm64.dmg"
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/Textify.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "Textify $VERSION" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
```

Create `script/release/notarize_dmg.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${TEXTIFY_NOTARY_PROFILE:?Set TEXTIFY_NOTARY_PROFILE}"

DMG_PATH="${1:?Usage: notarize_dmg.sh path/to/Textify.dmg}"

xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$TEXTIFY_NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH"
```

- [ ] **Step 2: Add validation script**

`script/release/validate_release.sh` must run credential-free checks:

```bash
#!/usr/bin/env bash
set -euo pipefail

swift test
swift build -c release --arch arm64
plutil -lint Resources/Info.plist
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Print :LSUIElement" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" Resources/Info.plist
! rg -n "SUFeedURL|SUPublicEDKey|Sparkle" Resources Sources Package.swift project.yml
! rg -n "Run Mock Dictation|Mock dictation|Developer Mode|Check for Updates|transcript history" Sources/Textify
lipo -archs .build/arm64-apple-macosx/release/Textify | rg '^arm64$'
```

- [ ] **Step 3: Verify Info.plist and entitlements**

Required `Resources/Info.plist` keys:

- `CFBundleIdentifier`: `io.github.Player0109.Textify`
- `CFBundleShortVersionString`: `1.1.0`
- `LSMinimumSystemVersion`: `14.0`
- `LSUIElement`: `true`
- `NSMicrophoneUsageDescription`

`Textify.entitlements` must not include `com.apple.security.app-sandbox`.

Create `script/release/ExportOptions.DeveloperID.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
```

Do not commit private notary credentials or local signing profiles.

- [ ] **Step 4: Verify release script dry run**

Run:

```bash
bash script/release/validate_release.sh
```

Expected: passes without Apple credentials.

- [ ] **Step 5: Commit**

```bash
git add project.yml Textify.entitlements Resources script/release
git commit -m "v1.1: add release packaging scripts"
```

## Task 12: Model Publishing Scripts And Docs

**Files:**

- Create: `script/models/sign_model_manifest.sh`
- Create: `script/models/verify_model_manifest.sh`
- Create: `docs/models/curated-models.md`
- Create: `docs/models/model-manifest-signing.md`
- Modify: `docs/RELEASING.md`

- [ ] **Step 1: Add model signing script**

`script/models/sign_model_manifest.sh` must require local-only secrets:

```bash
: "${TEXTIFY_MODEL_MANIFEST_PRIVATE_KEY_BASE64:?local private key required}"
: "${TEXTIFY_MODEL_MANIFEST_KEY_ID:?key id required}"
```

It must output `manifest.json.sig` with:

```json
{
  "signatureVersion": 1,
  "keyId": "textify-model-manifest-2026-primary",
  "algorithm": "Ed25519",
  "signatureBase64": "..."
}
```

Do not commit any private key file, seed, `.env`, or generated secret.

- [ ] **Step 2: Add model verification script**

`script/models/verify_model_manifest.sh` must verify:

- exactly one model entry
- model id `ggml-small.en-q5_1`
- HTTPS GitHub Release asset URL
- SHA-256 is present
- detached signature verifies against supplied public key

- [ ] **Step 3: Document curated model**

`docs/models/curated-models.md` must document:

- display name `Balanced - Whisper small.en q5_1`
- file `ggml-small.en-q5_1.bin`
- source `ggerganov/whisper.cpp`
- Textify GitHub Release asset URL shape
- SHA-256 comes from exact uploaded model bytes
- English only

- [ ] **Step 4: Verify scripts**

Run:

```bash
bash -n script/models/sign_model_manifest.sh
bash -n script/models/verify_model_manifest.sh
```

Expected: shell syntax passes.

- [ ] **Step 5: Commit**

```bash
git add script/models docs/models docs/RELEASING.md
git commit -m "v1.1: add model publishing workflow"
```

## Task 13: Public Docs, Privacy, Notices, And Manual QA

**Files:**

- Modify: `README.md`
- Create/Modify: `PRIVACY.md`
- Create/Modify: `CHANGELOG.md`
- Modify: `ACKNOWLEDGMENTS.md`
- Modify: `THIRD_PARTY_NOTICES.md`
- Create: `THIRD_PARTY_LICENSES/whisper.cpp.txt`
- Modify: `docs/MANUAL_QA.md`
- Modify: `docs/RELEASING.md`

- [ ] **Step 1: Update README**

README must state:

- macOS 14+, Apple Silicon only
- direct DMG install
- Right Command hold-to-dictate
- local whisper.cpp transcription
- one curated model download
- required permissions
- manual GitHub Release updates because Sparkle is deferred

- [ ] **Step 2: Add privacy policy**

`PRIVACY.md` must state:

- audio processed locally
- no transcript history
- no raw audio retention
- clipboard snapshot/restore only
- diagnostics redacted
- no automatic upload
- no Sparkle/system profile sending in V1.1

- [ ] **Step 3: Update manual QA**

`docs/MANUAL_QA.md` must include these release-blocking checks with checkboxes:

1. Fresh install from stapled DMG on macOS 14+ Apple Silicon.
2. Gatekeeper opens app without override.
3. No Dock icon by default.
4. Menu bar icon appears.
5. Onboarding installs and verifies `ggml-small.en-q5_1`.
6. Microphone permission flow works.
7. Accessibility permission flow works.
8. Input Monitoring permission flow works.
9. Right Command trigger test passes.
10. Dictation into TextEdit works.
11. Dictation into Notes or browser text field works.
12. Secure password field blocks insertion.
13. Cancelling during processing does not insert late text.
14. Clipboard is restored after paste when marker remains.
15. Clipboard is not overwritten if changed during paste.
16. Diagnostics export contains no transcript or clipboard content.
17. Launch at Login works if enabled.
18. Sparkle UI/framework is absent.
19. App binary is arm64 only.
20. DMG notarization/stapling validation passes.

- [ ] **Step 4: Verify docs have no impossible promises**

Run:

```bash
rg -n "Intel|Mac App Store|Sparkle auto|automatic update|history|multi-language|arbitrary model|per-app profile|encryption" README.md PRIVACY.md CHANGELOG.md docs
```

Expected: any match describes absence, deferral, or out-of-scope behavior accurately.

- [ ] **Step 5: Commit**

```bash
git add README.md PRIVACY.md CHANGELOG.md ACKNOWLEDGMENTS.md THIRD_PARTY_NOTICES.md THIRD_PARTY_LICENSES docs/MANUAL_QA.md docs/RELEASING.md
git commit -m "v1.1: update public release docs"
```

## Task 14: End-To-End Production Integration And Release Candidate

**Files:**

- Modify only files required to connect completed tasks.
- Update: `docs/implementation/coordination.md`
- Update: `docs/MANUAL_QA.md` with local pass/fail notes when manual checks are run.

- [ ] **Step 1: Run full automated verification**

```bash
swift test
swift build -c release --arch arm64
bash script/release/validate_release.sh
```

Expected: all pass.

- [ ] **Step 2: Launch staged app**

```bash
./script/build_and_run.sh --verify
```

Expected: app launches as a menu bar app.

- [ ] **Step 3: Manual smoke the local production path**

Run a local manual smoke with a verified dev model file:

1. Complete onboarding or mark test readiness using production paths.
2. Grant microphone, Accessibility, and Input Monitoring.
3. Hold Right Command for longer than 250 ms.
4. Speak one short English sentence.
5. Release Right Command.
6. Verify text is pasted into TextEdit.
7. Verify no transcript appears in UI.
8. Verify diagnostics contain only redacted fields.

- [ ] **Step 4: Verify secure-field and cancellation behavior**

Manual checks:

1. Focus a password field.
2. Attempt dictation.
3. Verify no pasteboard mutation and no insertion.
4. Start dictation and press Esc before release.
5. Verify audio is discarded and no late insertion occurs.

- [ ] **Step 5: Optional maintainer-machine release packaging**

Run only on maintainer machine with credentials:

```bash
TEXTIFY_DEVELOPMENT_TEAM="<TEAM_ID>" \
TEXTIFY_SIGNING_IDENTITY="Developer ID Application: <NAME> (<TEAM_ID>)" \
bash script/release/build_archive.sh

bash script/release/export_developer_id.sh
bash script/release/make_dmg.sh 1.1.0

TEXTIFY_NOTARY_PROFILE="TextifyNotary" \
bash script/release/notarize_dmg.sh build/release/Textify-1.1.0-arm64.dmg
```

Expected:

- Developer ID archive succeeds.
- DMG is created.
- Notarization is accepted.
- Stapling validates.
- `spctl` assessment passes.
- `Textify-1.1.0-arm64.dmg` and `.sha256` are produced.

- [ ] **Step 6: Record final integration status**

Append to `docs/implementation/coordination.md`:

```markdown
## V1.1 Integration Status

- Automated verification:
  - `swift test`: result recorded by integrator.
  - `swift build -c release --arch arm64`: result recorded by integrator.
  - `script/release/validate_release.sh`: result recorded by integrator.
- Manual local dictation smoke: result recorded by integrator.
- Maintainer-machine signing/notarization: not run unless credentials are present.
```

- [ ] **Step 7: Commit**

```bash
git add docs/implementation/coordination.md docs/MANUAL_QA.md
git commit -m "v1.1: complete production integration gate"
```

## Merge Gates

After Wave 0:

```bash
swift test --filter TextifyRuntimeTests
swift test
rg -n "import TextifyRuntime" Sources/TextifyAudio Sources/TextifyCore Sources/TextifyDiagnostics Sources/TextifyHotkeys Sources/TextifyInsertion Sources/TextifyModels Sources/TextifySettings Sources/TextifyTranscription
```

Expected: tests pass and `rg` prints no imports.

After Wave 1:

```bash
swift test --filter TextifyAudioTests
swift test --filter TextifyHotkeysTests
swift test --filter TextifyInsertionTests
swift test --filter TextifyModelsTests
swift test --filter TextifyTranscriptionTests
swift test --filter TextifySettingsTests
swift test --filter TextifyDiagnosticsTests
swift test
```

Expected: all tests pass.

After Wave 2:

```bash
swift test --filter TextifyRuntimeTests
swift test
```

Expected: runtime fake-driven integration passes, including stale cancellation prevention.

After Wave 3:

```bash
swift test
swift build
swift build -c release --arch arm64
rg -n "Run Mock Dictation|Mock dictation|Sparkle|Check for Updates|Developer Mode|transcript history" Sources/Textify
```

Expected: builds pass and Release-visible forbidden strings are absent.

After Wave 4:

```bash
swift test
bash script/release/validate_release.sh
bash -n script/models/sign_model_manifest.sh
bash -n script/models/verify_model_manifest.sh
```

Expected: validation passes without private credentials.

After Wave 5:

```bash
swift test
swift build -c release --arch arm64
bash script/release/validate_release.sh
./script/build_and_run.sh --verify
```

Expected: automated gates pass; manual QA is required before release readiness.

## Self-Review

Spec coverage:

- Runtime orchestration and readiness: Tasks 0, 7, 8.
- Audio capture: Task 1.
- Right Command/Input Monitoring: Task 2.
- Paste insertion and Accessibility target checks: Task 3.
- Model trust, download, install, and selected model: Task 4.
- Native whisper runtime: Task 5.
- Settings, diagnostics, retention, and no history: Task 6.
- App composition, onboarding, settings, overlay, and Release UI cleanup: Tasks 9 and 10.
- Launch at Login: Task 9.
- Sparkle deferral: Tasks 10, 11, 13.
- Release packaging, signing, notarization, DMG, docs, and manual QA: Tasks 11, 12, 13, 14.

Known final-release prerequisites that implementation can proceed without:

- Apple Developer ID certificate and notary credentials.
- Final app icon asset.
- Final uploaded GitHub Release model asset and SHA-256.
- Production model manifest signing private key.
- Clean-machine manual QA account.

These prerequisites block public release, not implementation. Scripts and docs must make the missing prerequisite explicit instead of silently skipping trust checks.
