# Textify V1 Parallel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Textify V1 as a native macOS menu bar dictation app using a mock-first vertical path, then replace mocks with real macOS and whisper.cpp boundaries.

**Architecture:** Textify is SwiftPM-first: pure logic lives in small internal library targets, the executable owns app composition, and the thin Xcode project is introduced only after the SwiftPM app path is working. Parallel agents must keep file ownership narrow and merge through explicit integration gates so independent targets can progress without shared-state churn.

**Tech Stack:** Swift 5.9+, SwiftPM, SwiftUI, AppKit, AVFoundation, ApplicationServices, ServiceManagement, CryptoKit, XCTest, JSON/UserDefaults/JSONL, Sparkle and whisper.cpp only in late milestones.

---

## Ground Rules

Every agent must read these files before editing:

- `docs/SPEC.md`
- `docs/superpowers/plans/2026-07-03-textify-v1-parallel-implementation.md`

The workspace currently contains only `docs/SPEC.md` and this plan. The first task creates the repo scaffold. No other task starts until Task 1 is merged.

Do not start with whisper.cpp, Sparkle, notarization, CGEventTap, or real cross-app insertion. Start with pure Swift targets and fakes.

No agent may edit another agent's owned paths without an integration handoff. If a task needs a shared interface changed, stop and update the plan or create a short handoff note in `docs/implementation/coordination.md`.

Each task must end with:

```bash
swift test
```

Expected result after each task: all tests pass.

When the repo is initialized, each task also ends with the exact commit command
listed in that task. Do not substitute a broad `git add .` for the listed paths.

## Parallelization Map

| Wave | Agents | Can Run In Parallel | Merge Gate |
| --- | --- | --- | --- |
| 0 | Task 1 | No | `Package.swift` and smoke tests pass |
| 1 | Tasks 2, 3, 4, 5, 6, 7 | Yes after Task 1 | Pure library targets and mock provider boundaries pass independently |
| 2 | Tasks 8, 9, 10 | Yes after Wave 1 | Shared fake-driven dictation path and core OS boundaries compile |
| 3 | Tasks 11, 12 | Yes after Wave 2 | Mock app launches and download scaffold passes |
| 4 | Tasks 13, then 14, then 15 | Serial | Native runtime, thin Xcode bundle, release checks, final integration |

## File Ownership

Task 1 owns scaffold files:

- `Package.swift`
- `.gitignore`
- `.codex/environments/environment.toml`
- `script/build_and_run.sh`
- `README.md`
- `LICENSE`
- `ACKNOWLEDGMENTS.md`
- `THIRD_PARTY_NOTICES.md`
- `AGENTS.md`
- `docs/implementation/coordination.md`
- source/test scaffold directories and the minimal SwiftUI menu bar app shell

Task 2 owns:

- `Sources/TextifyCore/PostProcessing/`
- `Sources/TextifyCore/Vocabulary/`
- `Sources/TextifyCore/Hallucination/`
- `Tests/TextifyCoreTests/PostProcessingTests.swift`

Task 3 owns:

- `Sources/TextifyDiagnostics/`
- `Tests/TextifyDiagnosticsTests/`

Task 4 owns:

- `Sources/TextifyModels/`
- `Tests/TextifyModelsTests/`
- `Tests/TextifyModelsTests/Fixtures/`

Task 5 owns:

- `Sources/TextifySettings/`
- `Tests/TextifySettingsTests/`

Task 6 owns:

- `Sources/TextifyAudio/`
- `Tests/TextifyAudioTests/`

Task 7 owns:

- `Sources/TextifyTranscription/`
- `Tests/TextifyTranscriptionTests/`

Task 8 owns:

- `Sources/TextifyCore/Dictation/`
- `Tests/TextifyCoreTests/DictationControllerTests.swift`

Task 9 owns:

- `Sources/TextifyInsertion/`
- `Tests/TextifyInsertionTests/`

Task 10 owns:

- `Sources/TextifyHotkeys/`
- `Tests/TextifyHotkeysTests/`

Task 11 owns:

- `Sources/Textify/App/`
- `Sources/Textify/UI/`
- `Sources/Textify/Overlay/`
- `Sources/Textify/Onboarding/`
- `Sources/Textify/SettingsUI/`

Task 12 owns:

- `Sources/TextifyModels/Downloads/`
- `Tests/TextifyModelsTests/DownloadTests.swift`

Task 13 owns:

- `Vendor/whisper.cpp/`
- `Sources/TextifyWhisperShim/`
- native additions under `Sources/TextifyTranscription/Native/`

Task 14 owns:

- `project.yml`
- `Textify.xcodeproj/`
- `Resources/`
- `Textify.entitlements`
- `script/generate_xcode_project.sh`
- `docs/RELEASING.md`
- `docs/MANUAL_QA.md`

Task 15 owns integration-only edits across targets after all prior tasks merge.

## Shared Interfaces Fixed By Task 1

Task 1 creates these files with minimal compiling definitions so parallel agents can build against stable names:

- `Sources/TextifyCore/TextifyCore.swift`
- `Sources/TextifyAudio/TextifyAudio.swift`
- `Sources/TextifyTranscription/TextifyTranscription.swift`
- `Sources/TextifyModels/TextifyModels.swift`
- `Sources/TextifyInsertion/TextifyInsertion.swift`
- `Sources/TextifyHotkeys/TextifyHotkeys.swift`
- `Sources/TextifyDiagnostics/TextifyDiagnostics.swift`
- `Sources/TextifySettings/TextifySettings.swift`
- `Sources/Textify/App/TextifyApp.swift`
- `Sources/Textify/App/AppDelegate.swift`
- `Sources/Textify/UI/MenuBarRoot.swift`

Each later task may add files in its owned directories. Public type names must stay stable unless the owning task updates every compile error in the same change.

## Task 1: Repo Scaffold

**Files:**

- Create: `Package.swift`
- Create: `.gitignore`
- Create: `.codex/environments/environment.toml`
- Create: `script/build_and_run.sh`
- Create: `README.md`
- Create: `LICENSE`
- Create: `ACKNOWLEDGMENTS.md`
- Create: `THIRD_PARTY_NOTICES.md`
- Create: `AGENTS.md`
- Create: `docs/implementation/coordination.md`
- Create: `Sources/TextifyCore/TextifyCore.swift`
- Create: `Sources/TextifyAudio/TextifyAudio.swift`
- Create: `Sources/TextifyTranscription/TextifyTranscription.swift`
- Create: `Sources/TextifyModels/TextifyModels.swift`
- Create: `Sources/TextifyInsertion/TextifyInsertion.swift`
- Create: `Sources/TextifyHotkeys/TextifyHotkeys.swift`
- Create: `Sources/TextifyDiagnostics/TextifyDiagnostics.swift`
- Create: `Sources/TextifySettings/TextifySettings.swift`
- Create: `Sources/Textify/App/TextifyApp.swift`
- Create: `Sources/Textify/App/AppDelegate.swift`
- Create: `Sources/Textify/UI/MenuBarRoot.swift`
- Create: `Tests/TextifyCoreTests/SmokeTests.swift`
- Create: `Tests/TextifyAudioTests/SmokeTests.swift`
- Create: `Tests/TextifyTranscriptionTests/SmokeTests.swift`
- Create: `Tests/TextifyModelsTests/SmokeTests.swift`
- Create: `Tests/TextifyInsertionTests/SmokeTests.swift`
- Create: `Tests/TextifyHotkeysTests/SmokeTests.swift`
- Create: `Tests/TextifyDiagnosticsTests/SmokeTests.swift`
- Create: `Tests/TextifySettingsTests/SmokeTests.swift`

- [ ] **Step 1: Initialize git**

Run:

```bash
git rev-parse --is-inside-work-tree || git init
```

Expected: either `true` or a new repository initialized at
`/Users/textify/Textify`.

- [ ] **Step 2: Create `Package.swift`**

Use this exact initial package shape:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Textify",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TextifyCore", targets: ["TextifyCore"]),
        .library(name: "TextifyAudio", targets: ["TextifyAudio"]),
        .library(name: "TextifyTranscription", targets: ["TextifyTranscription"]),
        .library(name: "TextifyModels", targets: ["TextifyModels"]),
        .library(name: "TextifyInsertion", targets: ["TextifyInsertion"]),
        .library(name: "TextifyHotkeys", targets: ["TextifyHotkeys"]),
        .library(name: "TextifyDiagnostics", targets: ["TextifyDiagnostics"]),
        .library(name: "TextifySettings", targets: ["TextifySettings"]),
        .executable(name: "Textify", targets: ["Textify"])
    ],
    targets: [
        .target(name: "TextifyCore"),
        .target(name: "TextifyAudio"),
        .target(name: "TextifyTranscription", dependencies: ["TextifyCore"]),
        .target(name: "TextifyModels", dependencies: ["TextifyDiagnostics"]),
        .target(name: "TextifyInsertion", dependencies: ["TextifyCore", "TextifyDiagnostics"]),
        .target(name: "TextifyHotkeys", dependencies: ["TextifyCore", "TextifyDiagnostics"]),
        .target(name: "TextifyDiagnostics"),
        .target(name: "TextifySettings", dependencies: ["TextifyModels"]),
        .executableTarget(
            name: "Textify",
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
        .testTarget(name: "TextifyCoreTests", dependencies: ["TextifyCore"]),
        .testTarget(name: "TextifyAudioTests", dependencies: ["TextifyAudio"]),
        .testTarget(name: "TextifyTranscriptionTests", dependencies: ["TextifyTranscription"]),
        .testTarget(name: "TextifyModelsTests", dependencies: ["TextifyModels"]),
        .testTarget(name: "TextifyInsertionTests", dependencies: ["TextifyInsertion"]),
        .testTarget(name: "TextifyHotkeysTests", dependencies: ["TextifyHotkeys"]),
        .testTarget(name: "TextifyDiagnosticsTests", dependencies: ["TextifyDiagnostics"]),
        .testTarget(name: "TextifySettingsTests", dependencies: ["TextifySettings"])
    ]
)
```

- [ ] **Step 3: Create source placeholders with real module symbols**

Each library file should expose one public namespace marker so imports are testable:

```swift
public enum TextifyCoreModule {
    public static let name = "TextifyCore"
}
```

Use the same pattern for each target, changing the enum and string to:

- `TextifyAudioModule`
- `TextifyTranscriptionModule`
- `TextifyModelsModule`
- `TextifyInsertionModule`
- `TextifyHotkeysModule`
- `TextifyDiagnosticsModule`
- `TextifySettingsModule`

Create `Sources/Textify/App/TextifyApp.swift` as the minimal SwiftUI menu bar app shell:

```swift
import SwiftUI

@main
struct TextifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Textify", systemImage: "text.bubble") {
            MenuBarRoot()
        }
    }
}
```

Create `Sources/Textify/App/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

Create `Sources/Textify/UI/MenuBarRoot.swift`:

```swift
import AppKit
import SwiftUI

struct MenuBarRoot: View {
    var body: some View {
        Button("Quit Textify") {
            NSApplication.shared.terminate(nil)
        }
    }
}
```

- [ ] **Step 4: Create smoke tests**

Example for `Tests/TextifyCoreTests/SmokeTests.swift`:

```swift
import XCTest
import TextifyCore

final class SmokeTests: XCTestCase {
    func testModuleName() {
        XCTAssertEqual(TextifyCoreModule.name, "TextifyCore")
    }
}
```

Create equivalent smoke tests for every library target.

- [ ] **Step 5: Create support files**

`.gitignore`:

```gitignore
.build/
.swiftpm/
DerivedData/
*.xcuserstate
*.xcworkspace/xcuserdata/
*.xcodeproj/xcuserdata/
.DS_Store
.spike/
Textify.app/
dist/
```

`script/build_and_run.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Textify"
BUNDLE_ID="io.github.Player0109.Textify"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_BUNDLE" >/dev/null

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
```

`.codex/environments/environment.toml`:

```toml
# THIS IS AUTOGENERATED. DO NOT EDIT MANUALLY
version = 1
name = "Textify"

[setup]
script = ""

[[actions]]
name = "Run"
icon = "run"
command = "./script/build_and_run.sh"
```

`docs/implementation/coordination.md`:

```markdown
# Textify Implementation Coordination

This file records cross-agent handoffs during implementation.

## Current Merge Gate

Task 1 must merge before parallel Wave 1 work begins.
```

- [ ] **Step 6: Build and test**

Run:

```bash
chmod +x script/build_and_run.sh
swift build
swift test
./script/build_and_run.sh --verify
```

Expected: build succeeds, all smoke tests pass, and `dist/Textify.app` launches as a real app bundle.

- [ ] **Step 7: Commit**

```bash
git add Package.swift .gitignore .codex script README.md LICENSE ACKNOWLEDGMENTS.md THIRD_PARTY_NOTICES.md AGENTS.md docs/implementation Sources Tests
git commit -m "task-1: scaffold SwiftPM workspace"
```

## Task 2: Pure Text Pipeline

**Files:**

- Create: `Sources/TextifyCore/PostProcessing/TextSegment.swift`
- Create: `Sources/TextifyCore/PostProcessing/SpokenCommand.swift`
- Create: `Sources/TextifyCore/PostProcessing/PostProcessingPipeline.swift`
- Create: `Sources/TextifyCore/Vocabulary/VocabularyReplacement.swift`
- Create: `Sources/TextifyCore/Hallucination/HallucinationFilter.swift`
- Create: `Tests/TextifyCoreTests/PostProcessingTests.swift`

- [ ] **Step 1: Write failing tests**

Create tests that prove the V1 text rules:

```swift
import XCTest
import TextifyCore

final class PostProcessingTests: XCTestCase {
    func testPunctuationCommandsAndSentenceCapitalizationDoesNotInferProperNouns() {
        let pipeline = PostProcessingPipeline()
        let output = pipeline.process(
            rawText: "hello comma this is textify period new paragraph i am testing",
            replacements: []
        )
        XCTAssertEqual(output, "Hello, this is textify.\n\nI am testing")
    }

    func testVocabularyReplacementCanExplicitlyCapitalizeTextify() {
        let pipeline = PostProcessingPipeline()
        let output = pipeline.process(
            rawText: "hello comma this is textify period",
            replacements: [
                VocabularyReplacement(trigger: "textify", replacement: "Textify")
            ]
        )
        XCTAssertEqual(output, "Hello, this is Textify.")
    }

    func testReplacementSpanIsProtectedFromCapitalization() {
        let pipeline = PostProcessingPipeline()
        let output = pipeline.process(
            rawText: "open player zero one zero nine period",
            replacements: [
                VocabularyReplacement(trigger: "player zero one zero nine", replacement: "Player0109")
            ]
        )
        XCTAssertEqual(output, "Open Player0109.")
    }

    func testHallucinationDiscard() {
        let filter = HallucinationFilter()
        XCTAssertTrue(filter.shouldDiscard(text: "Thanks for watching!", noSpeechProbability: 0.92, averageLogProbability: -1.4, compressionRatio: 2.0))
        XCTAssertFalse(filter.shouldDiscard(text: "Send this note", noSpeechProbability: 0.05, averageLogProbability: -0.2, compressionRatio: 1.1))
    }
}
```

- [ ] **Step 2: Run failing test**

```bash
swift test --filter TextifyCoreTests.PostProcessingTests
```

Expected: compile fails because the post-processing types do not exist.

- [ ] **Step 3: Implement types and pipeline**

Use these public types:

```swift
public enum TextSegment: Equatable {
    case mutable(String)
    case protected(String)
}

public struct VocabularyReplacement: Equatable, Codable, Sendable {
    public let trigger: String
    public let replacement: String

    public init(trigger: String, replacement: String) {
        self.trigger = trigger
        self.replacement = replacement
    }
}
```

Implement `SpokenCommand` as a fixed table matching `docs/SPEC.md` section 23.1. Implement `PostProcessingPipeline.process(rawText:replacements:)` in this order:

1. command normalization
2. adjacent punctuation dedup
3. light filler cleanup
4. vocabulary replacements with protected spans
5. final whitespace/capitalization pass

The final capitalization pass must not special-case product names, app names,
proper nouns, or acronyms. Lowercase `textify` stays `textify` unless a
`VocabularyReplacement(trigger: "textify", replacement: "Textify")` is provided.

Implement `HallucinationFilter.shouldDiscard(text:noSpeechProbability:averageLogProbability:compressionRatio:)` using:

- discard if `noSpeechProbability > 0.60`
- discard if `averageLogProbability < -1.00`
- discard if `compressionRatio > 2.40`
- discard common boilerplate phrase `thanks for watching`

- [ ] **Step 4: Verify**

```bash
swift test --filter TextifyCoreTests.PostProcessingTests
swift test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TextifyCore Tests/TextifyCoreTests
git commit -m "task-2: add text post-processing pipeline"
```

## Task 3: Diagnostics And Privacy Schema

**Files:**

- Create: `Sources/TextifyDiagnostics/DiagnosticEvent.swift`
- Create: `Sources/TextifyDiagnostics/DiagnosticsLogger.swift`
- Create: `Sources/TextifyDiagnostics/DiagnosticsExporter.swift`
- Create: `Tests/TextifyDiagnosticsTests/DiagnosticsTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import TextifyDiagnostics

final class DiagnosticsTests: XCTestCase {
    func testInsertionEventContainsNoContentFields() throws {
        let event = DiagnosticEvent.insertionAttempt(
            textLengthBucket: "201-500",
            pasteboardSnapshotSucceeded: true,
            pasteboardWriteSucceeded: true,
            pasteEventPosted: true,
            fallbackAttempted: false,
            fallbackBlockedReason: "paste_outcome_unobservable",
            durationMs: 123
        )

        let data = try JSONEncoder().encode(event)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("transcript"))
        XCTAssertFalse(json.contains("clipboard"))
        XCTAssertFalse(json.contains("bundleIdentifier"))
        XCTAssertFalse(json.contains("text\":\""))
    }

    func testExportIsSingleJSONDocument() throws {
        let exporter = DiagnosticsExporter()
        let exported = try exporter.export(events: [.appStarted(appVersion: "1.0.0", macOSVersion: "14.0")])
        XCTAssertTrue(exported.keys.contains("events"))
        XCTAssertEqual(exported["formatVersion"] as? Int, 1)
    }
}
```

- [ ] **Step 2: Run failing tests**

```bash
swift test --filter TextifyDiagnosticsTests
```

Expected: compile fails because diagnostics types do not exist.

- [ ] **Step 3: Implement closed event enum**

Create `DiagnosticEvent` with only typed cases:

- `appStarted(appVersion:macOSVersion:)`
- `insertionAttempt(textLengthBucket:pasteboardSnapshotSucceeded:pasteboardWriteSucceeded:pasteEventPosted:fallbackAttempted:fallbackBlockedReason:durationMs:)`
- `dictationBlockedExcludedApp`
- `launchAtLoginChange(requestedAction:statusBefore:statusAfter:appLocationCategory:succeeded:errorDomain:errorCode:)`
- `modelLoad(modelID:tier:durationMs:result:)`

Use custom `Encodable` to emit a closed JSON object. Do not define fields named `message`, `details`, `content`, `text`, `transcript`, or `clipboardContents`.

- [ ] **Step 4: Implement logger/exporter**

`DiagnosticsLogger` writes one JSON object per line to a caller-provided directory. `DiagnosticsExporter.export(events:)` returns a dictionary:

```swift
[
    "formatVersion": 1,
    "events": [[String: Any]]
]
```

Use `JSONSerialization` for the export dictionary so tests can inspect it without writing files.

- [ ] **Step 5: Verify**

```bash
swift test --filter TextifyDiagnosticsTests
swift test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/TextifyDiagnostics Tests/TextifyDiagnosticsTests
git commit -m "task-3: add privacy-safe diagnostics schema"
```

## Task 4: Model Manifest System

**Files:**

- Create: `Sources/TextifyModels/Manifest/ModelManifest.swift`
- Create: `Sources/TextifyModels/Manifest/ManifestSignature.swift`
- Create: `Sources/TextifyModels/Manifest/ManifestVerifier.swift`
- Create: `Sources/TextifyModels/Storage/InstalledModelsStore.swift`
- Create: `Tests/TextifyModelsTests/ManifestTests.swift`
- Create: `Tests/TextifyModelsTests/ManifestSignatureTests.swift`
- Create: `Tests/TextifyModelsTests/Fixtures/Models/manifest.json`
- Create: `Tests/TextifyModelsTests/Fixtures/Models/manifest_unknown_field.json`
- Create: `Tests/TextifyModelsTests/Fixtures/Models/manifest.json.sig`
- Create: `Tests/TextifyModelsTests/Fixtures/Models/manifest.fixture-public-key.base64`
- Modify: `Package.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import TextifyModels

final class ManifestTests: XCTestCase {
    private static func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: nil,
                subdirectory: "Fixtures/Models"
            )
        )
        return try Data(contentsOf: url)
    }

    private static var validManifestData: Data {
        get throws {
            try fixtureData("manifest.json")
        }
    }

    private static var validManifestJSONWithUnknownField: String {
        get throws {
            String(decoding: try fixtureData("manifest_unknown_field.json"), as: UTF8.self)
        }
    }

    func testManifestParsesInitialCuratedModelShape() throws {
        let manifest = try ModelManifest.decode(try Self.validManifestData)
        XCTAssertEqual(manifest.manifestVersion, 1)
        XCTAssertEqual(manifest.models.first?.id, "whisper-base-en-fast")
        XCTAssertEqual(manifest.models.first?.runtimeParameters.language, "en")
        XCTAssertEqual(manifest.models.first?.runtimeParameters.temperatureFallback, [])
    }

    func testUnknownFieldsAreRejected() throws {
        let data = Data((try Self.validManifestJSONWithUnknownField).utf8)
        XCTAssertThrowsError(try ModelManifest.decode(data))
    }
}
```

- [ ] **Step 2: Run failing tests**

```bash
swift test --filter TextifyModelsTests.ManifestTests
```

Expected: compile fails because manifest types do not exist.

Fixture files must be included in the `TextifyModelsTests` target through `Bundle.module`. Update the test target in `Package.swift`:

```swift
.testTarget(
    name: "TextifyModelsTests",
    dependencies: ["TextifyModels"],
    resources: [
        .process("Fixtures")
    ]
)
```

`manifest.json` must be a complete valid one-model manifest matching `docs/SPEC.md` section 22, using `whisper-base-en-fast`, `runtimeParameters.language == "en"`, and `temperatureFallback: []`.

`manifest_unknown_field.json` must be identical in shape except for one additional top-level key named `unexpectedFieldForStrictSchemaTest`. Do not use this fixture for signature tests.

`manifest.json.sig` must be a detached JSON signature envelope whose `contentSHA256` is the SHA-256 of the exact bytes in `manifest.json`.

`manifest.fixture-public-key.base64` must contain the non-production Ed25519 public key used only by tests.

- [ ] **Step 3: Implement strict Codable structs**

Implement:

- `ModelManifest`
- `ModelEntry`
- `ModelFile`
- `ModelLicense`
- `ModelProvenance`
- `RuntimeParameters`
- `HallucinationThresholds`
- `ManifestSignature`

Implement strict unknown-key rejection by decoding to `[String: JSONValue]` first, comparing key sets, then decoding typed structs.

- [ ] **Step 4: Implement signature verification**

Implement:

```swift
public struct ManifestVerifier {
    public func canonicalPayload(signature: ManifestSignature) -> Data
    public func verify(manifestData: Data, signatureData: Data, publicKeyBase64: String) throws
}
```

Output must exactly match:

```text
TEXTIFY-MODEL-MANIFEST-SIGNATURE-V1
signatureVersion=1
signatureType=io.github.Player0109.Textify.model-manifest
algorithm=Ed25519
keyId=model-manifest-v1
manifestFile=manifest.json
contentType=application/vnd.textify.model-manifest+json;version=1
contentSHA256=<hash>
```

with a final newline.

Implement and test strict `.sig` parsing, SHA-256 content hash comparison,
canonical payload construction, Ed25519 verification with CryptoKit, rejection
of tampered manifest bytes, and rejection of unknown fields in both manifest and
signature JSON.

- [ ] **Step 5: Verify**

```bash
swift test --filter TextifyModelsTests
swift test --filter TextifyModelsTests.ManifestSignatureTests
swift test
```

Expected: all tests pass. CryptoKit Ed25519 verification is part of Task 4. Task 12 must reuse `ManifestVerifier` for downloaded manifests and must not add a second verification path.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/TextifyModels Tests/TextifyModelsTests
git commit -m "task-4: add strict model manifest parser"
```

## Task 5: Settings Persistence

**Files:**

- Create: `Sources/TextifySettings/AppPreferences.swift`
- Create: `Sources/TextifySettings/SettingsStore.swift`
- Create: `Sources/TextifySettings/ExcludedApp.swift`
- Create: `Sources/TextifySettings/MicrophoneSelection.swift`
- Create: `Tests/TextifySettingsTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import TextifySettings

final class SettingsStoreTests: XCTestCase {
    func testDefaultsMatchV1Spec() throws {
        let store = SettingsStore(storage: .memory)
        let preferences = store.load()
        XCTAssertEqual(preferences.trigger, .rightCommand)
        XCTAssertEqual(preferences.microphoneSelection, .systemDefault)
        XCTAssertFalse(preferences.showInDock)
        XCTAssertTrue(preferences.launchAtLoginRequestedByOnboarding)
        XCTAssertTrue(preferences.excludedApps.isEmpty)
    }

    func testResetOnboardingDoesNotDeleteUserData() throws {
        let store = SettingsStore(storage: .memory)
        var preferences = store.load()
        preferences.onboardingCompleted = true
        preferences.excludedApps = [ExcludedApp(bundleIdentifier: "com.example.App", displayName: "Example", lastKnownPath: "/Applications/Example.app")]
        store.save(preferences)

        store.resetOnboarding()
        let reloaded = store.load()
        XCTAssertFalse(reloaded.onboardingCompleted)
        XCTAssertEqual(reloaded.excludedApps.count, 1)
    }
}
```

- [ ] **Step 2: Run failing tests**

```bash
swift test --filter TextifySettingsTests
```

Expected: compile fails because settings types do not exist.

- [ ] **Step 3: Implement models**

Implement:

- `AppPreferences`
- `TriggerPreference`
- `MicrophoneSelection`
- `ExcludedApp`
- `SettingsStore`

Use `Codable` JSON for file-backed persistence and an in-memory mode for tests.

- [ ] **Step 4: Verify**

```bash
swift test --filter TextifySettingsTests
swift test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TextifySettings Tests/TextifySettingsTests
git commit -m "task-5: add settings persistence"
```

## Task 6: Audio Pure Logic

**Files:**

- Create: `Sources/TextifyAudio/CanonicalAudioBuffer.swift`
- Create: `Sources/TextifyAudio/SpeechActivityDetector.swift`
- Create: `Sources/TextifyAudio/EdgeSilenceTrimmer.swift`
- Create: `Sources/TextifyAudio/MicrophoneDevice.swift`
- Create: `Tests/TextifyAudioTests/SpeechActivityDetectorTests.swift`
- Create: `Tests/TextifyAudioTests/EdgeSilenceTrimmerTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import TextifyAudio

final class SpeechActivityDetectorTests: XCTestCase {
    func testSustainedSpeechMarksDetected() {
        var detector = SpeechActivityDetector()
        let quiet = Array(repeating: Float(-60.0), count: 4)
        let speech = Array(repeating: Float(-35.0), count: 6)
        for db in quiet { detector.ingest(frameRMSdBFS: db) }
        for db in speech { detector.ingest(frameRMSdBFS: db) }
        XCTAssertTrue(detector.speechDetected)
    }

    func testShortClickDoesNotMarkSpeech() {
        var detector = SpeechActivityDetector()
        detector.ingest(frameRMSdBFS: -20.0)
        XCTAssertFalse(detector.speechDetected)
    }
}
```

- [ ] **Step 2: Run failing tests**

```bash
swift test --filter TextifyAudioTests
```

Expected: compile fails because audio pure logic does not exist.

- [ ] **Step 3: Implement pure audio models**

Implement:

- `CanonicalAudioBuffer(sampleRate: 16000, channelCount: 1, samples: [Float])`
- `SpeechActivityDetector` with 20 ms frame semantics, 80 ms startup grace, `max(noiseFloor + 12 dB, -45 dBFS)`, and 120 ms sustained detection.
- `EdgeSilenceTrimmer` with edge-only trimming and 150 ms safety pad.
- `MicrophoneDevice` and `MicrophoneSelection` bridge types only if Task 5 exposes compatible selection.

- [ ] **Step 4: Verify**

```bash
swift test --filter TextifyAudioTests
swift test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TextifyAudio Tests/TextifyAudioTests
git commit -m "task-6: add audio speech detection logic"
```

## Task 7: Transcription Provider And Mock Runtime

**Files:**

- Create: `Sources/TextifyTranscription/TranscriptionProvider.swift`
- Create: `Sources/TextifyTranscription/TranscriptionResult.swift`
- Create: `Sources/TextifyTranscription/MockTranscriptionProvider.swift`
- Create: `Sources/TextifyTranscription/WhisperRuntimeState.swift`
- Create: `Tests/TextifyTranscriptionTests/MockTranscriptionTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import TextifyTranscription

final class MockTranscriptionTests: XCTestCase {
    func testMockProviderReturnsQueuedResult() async throws {
        let provider = MockTranscriptionProvider(results: [
            TranscriptionResult(text: "hello period", noSpeechProbability: 0.01, averageLogProbability: -0.1, compressionRatio: 1.0)
        ])
        let result = try await provider.transcribe(.emptyForTests)
        XCTAssertEqual(result.text, "hello period")
    }
}
```

- [ ] **Step 2: Run failing tests**

```bash
swift test --filter TextifyTranscriptionTests
```

Expected: compile fails because transcription types do not exist.

- [ ] **Step 3: Implement provider boundary**

Define:

```swift
public protocol TranscriptionProvider: Sendable {
    func transcribe(_ audio: TranscriptionAudioBuffer) async throws -> TranscriptionResult
}
```

Add `TranscriptionAudioBuffer` in this target to avoid a dependency on AVFoundation. The real audio bridge can map from `TextifyAudio.CanonicalAudioBuffer` in an integration task.

Implement `MockTranscriptionProvider` as an actor with queued results.

- [ ] **Step 4: Verify**

```bash
swift test --filter TextifyTranscriptionTests
swift test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TextifyTranscription Tests/TextifyTranscriptionTests
git commit -m "task-7: add transcription provider boundary"
```

## Task 8: Dictation State Machine With Fakes

**Files:**

- Create: `Sources/TextifyCore/Dictation/DictationController.swift`
- Create: `Sources/TextifyCore/Dictation/DictationState.swift`
- Create: `Sources/TextifyCore/Dictation/DictationEvent.swift`
- Create: `Sources/TextifyCore/Dictation/DictationFakes.swift`
- Create: `Tests/TextifyCoreTests/DictationControllerTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import TextifyCore

final class DictationControllerTests: XCTestCase {
    func testTapBeforeThresholdDoesNothing() async {
        let controller = DictationController.fakingEverything()
        await controller.handle(.triggerDown(timestampMs: 0))
        await controller.handle(.triggerUp(timestampMs: 120))
        XCTAssertEqual(await controller.state, .idle)
        XCTAssertEqual(await controller.fakeInsertion.insertedTexts, [])
    }

    func testShortcutBeforeSpeechCancels() async {
        let controller = DictationController.fakingEverything()
        await controller.handle(.triggerDown(timestampMs: 0))
        await controller.handle(.activationThresholdPassed(timestampMs: 250))
        await controller.handle(.nonTriggerKeyDown(timestampMs: 300, isModifierOnly: false))
        await controller.handle(.triggerUp(timestampMs: 350))
        XCTAssertEqual(await controller.fakeInsertion.insertedTexts, [])
    }

    func testSpeechThenReleaseTranscribesAndInserts() async {
        let controller = DictationController.fakingEverything(transcript: "hello period")
        await controller.handle(.triggerDown(timestampMs: 0))
        await controller.handle(.activationThresholdPassed(timestampMs: 250))
        await controller.handle(.speechDetected(timestampMs: 400))
        await controller.handle(.triggerUp(timestampMs: 900))
        XCTAssertEqual(await controller.fakeInsertion.insertedTexts, ["hello period"])
    }
}
```

- [ ] **Step 2: Run failing tests**

```bash
swift test --filter TextifyCoreTests.DictationControllerTests
```

Expected: compile fails because dictation controller types do not exist.

- [ ] **Step 3: Implement state machine**

Implement states:

- `idle`
- `armed`
- `recording(speechDetected: Bool)`
- `processing`
- `inserting`
- `error(DictationError)`

Implement event handling for:

- accidental tap
- shortcut before activation
- shortcut after activation before speech
- Esc cancel
- release after speech
- release with no speech
- busy trigger ignored

- [ ] **Step 4: Verify**

```bash
swift test --filter TextifyCoreTests.DictationControllerTests
swift test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TextifyCore/Dictation Tests/TextifyCoreTests/DictationControllerTests.swift
git commit -m "task-8: add fake-driven dictation state machine"
```

## Task 9: Insertion Boundary

**Files:**

- Create: `Sources/TextifyInsertion/InsertionService.swift`
- Create: `Sources/TextifyInsertion/PasteboardClient.swift`
- Create: `Sources/TextifyInsertion/EventPoster.swift`
- Create: `Sources/TextifyInsertion/InsertionPolicy.swift`
- Create: `Tests/TextifyInsertionTests/InsertionPolicyTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import TextifyInsertion

final class InsertionPolicyTests: XCTestCase {
    func testDoesNotFallbackAfterPasteWasPosted() {
        let decision = InsertionPolicy().fallbackDecision(
            pasteEventPosted: true,
            textLength: 50,
            containsControlCharacters: false,
            targetStillMatches: true,
            secureFieldDetected: false
        )
        XCTAssertEqual(decision, .doNotFallback(reason: "paste_outcome_unobservable"))
    }

    func testFallbackAllowedOnlyForShortPlainTextBeforePaste() {
        let decision = InsertionPolicy().fallbackDecision(
            pasteEventPosted: false,
            textLength: 120,
            containsControlCharacters: false,
            targetStillMatches: true,
            secureFieldDetected: false
        )
        XCTAssertEqual(decision, .fallbackWithUnicodeChunks(maxScalarsPerChunk: 20))
    }
}
```

- [ ] **Step 2: Run failing tests**

```bash
swift test --filter TextifyInsertionTests
```

Expected: compile fails because insertion types do not exist.

- [ ] **Step 3: Implement insertion policy and protocols**

Implement:

- `InsertionService`
- `PasteboardClient`
- `EventPoster`
- `InsertionPolicy`
- `FallbackDecision`

Keep AppKit pasteboard and CGEvent posting out of this task. Use protocols only.

- [ ] **Step 4: Verify**

```bash
swift test --filter TextifyInsertionTests
swift test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TextifyInsertion Tests/TextifyInsertionTests
git commit -m "task-9: add insertion fallback policy"
```

## Task 10: Hotkey Trigger State

**Files:**

- Create: `Sources/TextifyHotkeys/TriggerPreference.swift`
- Create: `Sources/TextifyHotkeys/TriggerEvent.swift`
- Create: `Sources/TextifyHotkeys/TriggerStateMachine.swift`
- Create: `Tests/TextifyHotkeysTests/TriggerStateMachineTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import TextifyHotkeys

final class TriggerStateMachineTests: XCTestCase {
    func testRightCommandHoldActivatesAfterThreshold() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        XCTAssertEqual(machine.handle(.triggerDown(timestampMs: 0)), .startActivationTimer(delayMs: 250))
        XCTAssertEqual(machine.handle(.timerFired(timestampMs: 250)), .beginRecording)
    }

    func testNonTriggerKeyBeforeThresholdCancelsAsShortcut() {
        var machine = TriggerStateMachine(trigger: .rightCommand)
        _ = machine.handle(.triggerDown(timestampMs: 0))
        XCTAssertEqual(machine.handle(.nonTriggerKeyDown(timestampMs: 120, isModifierOnly: false)), .cancelAsShortcut)
    }
}
```

- [ ] **Step 2: Run failing tests**

```bash
swift test --filter TextifyHotkeysTests
```

Expected: compile fails because trigger types do not exist.

- [ ] **Step 3: Implement pure trigger state**

Implement triggers:

- right command
- right option
- right control
- control space

Implement pure state only. Do not create `CGEventTap` in this task.

- [ ] **Step 4: Verify**

```bash
swift test --filter TextifyHotkeysTests
swift test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TextifyHotkeys Tests/TextifyHotkeysTests
git commit -m "task-10: add pure trigger state machine"
```

## Task 11: Minimal Menu Bar App UI With Mocks

**Files:**

- Create: `Sources/Textify/App/AppServices.swift`
- Create: `Sources/Textify/SettingsUI/SettingsRootView.swift`
- Create: `Sources/Textify/Onboarding/OnboardingRootView.swift`
- Create: `Sources/Textify/Overlay/RecordingOverlayWindow.swift`
- Modify: `Sources/Textify/App/TextifyApp.swift`
- Modify: `Sources/Textify/App/AppDelegate.swift`
- Modify: `Sources/Textify/UI/MenuBarRoot.swift`

- [ ] **Step 1: Extend the Task 1 SwiftUI app shell**

Task 1 already created the `@main` SwiftUI menu bar app. This task extends that
app shell with the settings scene and mock UI surfaces.

Updated app entry:

```swift
import SwiftUI

@main
struct TextifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Textify", systemImage: "text.bubble") {
            MenuBarRoot()
        }

        Settings {
            SettingsRootView()
        }
    }
}
```

- [ ] **Step 2: Keep app delegate activation policy**

`AppDelegate` still sets accessory activation unless settings later request Dock mode. In this mock milestone, hardcode accessory:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

- [ ] **Step 3: Implement minimal menu and settings**

`MenuBarRoot` contains:

- `Settings...`
- `Check for Updates...`
- `About Textify`
- `Quit Textify`

`SettingsRootView` uses `TabView` with General, Dictation, Models, Vocabulary, Privacy, Advanced.

- [ ] **Step 4: Build and smoke run**

```bash
swift build
./script/build_and_run.sh --verify
```

Expected: app launches as a menu bar process through the staged `.app` bundle. Stop it manually after verifying launch.

- [ ] **Step 5: Commit**

```bash
git add Sources/Textify
git commit -m "task-11: add mock menu bar SwiftUI app"
```

## Task 12: Model Downloads

**Files:**

- Create: `Sources/TextifyModels/Downloads/ModelDownloader.swift`
- Create: `Sources/TextifyModels/Downloads/DownloadState.swift`
- Create: `Sources/TextifyModels/Downloads/DownloadResumeMetadata.swift`
- Create: `Tests/TextifyModelsTests/DownloadTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import TextifyModels

final class DownloadTests: XCTestCase {
    func testFreeSpaceRule() {
        XCTAssertEqual(ModelDownloader.requiredFreeBytes(modelSizeBytes: 1_000), 500_001_000)
        XCTAssertEqual(ModelDownloader.requiredFreeBytes(modelSizeBytes: 4_000_000_000), 4_800_000_000)
    }

    func testResumeRequiresMatchingValidators() {
        let metadata = DownloadResumeMetadata(modelID: "balanced", url: "https://example.com/model.bin", expectedSize: 10, sha256: "abc", eTag: "v1", lastModified: nil, bytesDownloaded: 5)
        XCTAssertTrue(metadata.canResume(url: "https://example.com/model.bin", expectedSize: 10, eTag: "v1", lastModified: nil))
        XCTAssertFalse(metadata.canResume(url: "https://example.com/model.bin", expectedSize: 10, eTag: "v2", lastModified: nil))
    }
}
```

- [ ] **Step 2: Run failing tests**

```bash
swift test --filter TextifyModelsTests.DownloadTests
```

Expected: compile fails because download types do not exist.

- [ ] **Step 3: Implement download state and policies**

Implement:

- `DownloadPhase`
- `DownloadState`
- `DownloadResumeMetadata`
- `ModelDownloader.requiredFreeBytes(modelSizeBytes:)`

Keep actual `URLSession` download small and injectable. Use a protocol `DownloadTransport` so tests use fixture data.

Manifest downloads must reuse the `ManifestVerifier` created in Task 4 for
signature verification. Do not add a second manifest signature verification
path in `ModelDownloader`.

- [ ] **Step 4: Verify**

```bash
swift test --filter TextifyModelsTests.DownloadTests
swift test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TextifyModels/Downloads Tests/TextifyModelsTests/DownloadTests.swift
git commit -m "task-12: add model download policies"
```

## Task 13: Native whisper.cpp Integration

**Files:**

- Create: `Vendor/whisper.cpp/UPSTREAM.md`
- Create: `Vendor/whisper.cpp/README.TEXTIFY.md`
- Create: `Vendor/whisper.cpp/LICENSE`
- Create: `Vendor/whisper.cpp/spm/include/TextifyWhisperVendor.h`
- Create: `Vendor/whisper.cpp/spm/include/module.modulemap`
- Create: `Sources/TextifyWhisperShim/include/TextifyWhisperShim.h`
- Create: `Sources/TextifyWhisperShim/include/module.modulemap`
- Create: `Sources/TextifyWhisperShim/TextifyWhisperShim.mm`
- Create: `Sources/TextifyTranscription/Native/WhisperRuntime.swift`
- Modify: `Package.swift`
- Modify: `THIRD_PARTY_NOTICES.md`
- Modify: `ACKNOWLEDGMENTS.md`

- [ ] **Step 1: Prepare package targets**

SwiftPM owns every native source file and native build flag. Xcode consumes SwiftPM products only and must not duplicate vendored file membership or native compile/link flags.

Keep this boundary:

```text
Swift TextifyTranscription
  -> C module TextifyWhisperShim
    -> C/C++/ObjC vendor target WhisperCppVendor
      -> pinned Vendor/whisper.cpp snapshot
```

Swift code imports only `TextifyWhisperShim`, never `whisper.h` or C++ headers directly.

Add package-wide standards:

```swift
cLanguageStandard: .c11,
cxxLanguageStandard: .cxx17
```

Add product:

```swift
.library(name: "TextifyWhisperShim", targets: ["TextifyWhisperShim"])
```

Modify `TextifyTranscription`:

```swift
.target(
    name: "TextifyTranscription",
    dependencies: [
        "TextifyCore",
        "TextifyWhisperShim"
    ]
)
```

Add targets:

```swift
.target(
    name: "WhisperCppVendor",
    path: "Vendor/whisper.cpp",
    exclude: [
        "bindings",
        "examples",
        "models",
        "samples",
        "tests",
        "src/coreml",
        "src/openvino",
        "ggml/src/ggml-cuda",
        "ggml/src/ggml-vulkan",
        "ggml/src/ggml-sycl",
        "ggml/src/ggml-opencl"
    ],
    sources: [
        "src/whisper.cpp",
        "ggml/src/ggml.c",
        "ggml/src/ggml.cpp",
        "ggml/src/ggml-alloc.c",
        "ggml/src/ggml-backend.cpp",
        "ggml/src/ggml-backend-reg.cpp",
        "ggml/src/ggml-backend-meta.cpp",
        "ggml/src/ggml-opt.cpp",
        "ggml/src/ggml-threading.cpp",
        "ggml/src/ggml-quants.c",
        "ggml/src/gguf.cpp",
        "ggml/src/ggml-cpu/ggml-cpu.c",
        "ggml/src/ggml-cpu/ggml-cpu.cpp",
        "ggml/src/ggml-cpu/binary-ops.cpp",
        "ggml/src/ggml-cpu/unary-ops.cpp",
        "ggml/src/ggml-cpu/ops.cpp",
        "ggml/src/ggml-cpu/vec.cpp",
        "ggml/src/ggml-cpu/traits.cpp",
        "ggml/src/ggml-cpu/quants.c",
        "ggml/src/ggml-cpu/repack.cpp",
        "ggml/src/ggml-cpu/hbm.cpp",
        "ggml/src/ggml-metal/ggml-metal.m"
    ],
    publicHeadersPath: "spm/include",
    cSettings: whisperCSettings,
    cxxSettings: whisperCXXSettings,
    linkerSettings: whisperLinkerSettings
),
.target(
    name: "TextifyWhisperShim",
    dependencies: ["WhisperCppVendor"],
    path: "Sources/TextifyWhisperShim",
    publicHeadersPath: "include",
    cSettings: whisperShimCSettings,
    cxxSettings: whisperShimCXXSettings,
    linkerSettings: whisperLinkerSettings
)
```

Define settings in `Package.swift`:

```swift
let whisperDefines: [CSetting] = [
    .define("GGML_USE_CPU"),
    .define("GGML_USE_ACCELERATE"),
    .define("GGML_USE_METAL"),
    .define("GGML_SCHED_MAX_COPIES", to: "4"),
    .define("_DARWIN_C_SOURCE"),
    .headerSearchPath("include"),
    .headerSearchPath("src"),
    .headerSearchPath("ggml/include"),
    .headerSearchPath("ggml/src"),
    .headerSearchPath("ggml/src/ggml-cpu"),
    .headerSearchPath("ggml/src/ggml-metal")
]

let whisperCXXDefines: [CXXSetting] = [
    .define("GGML_USE_CPU"),
    .define("GGML_USE_ACCELERATE"),
    .define("GGML_USE_METAL"),
    .define("GGML_SCHED_MAX_COPIES", to: "4"),
    .define("_DARWIN_C_SOURCE"),
    .headerSearchPath("include"),
    .headerSearchPath("src"),
    .headerSearchPath("ggml/include"),
    .headerSearchPath("ggml/src"),
    .headerSearchPath("ggml/src/ggml-cpu"),
    .headerSearchPath("ggml/src/ggml-metal")
]

let nativeWarningSuppressions = [
    "-Wno-shorten-64-to-32",
    "-Wno-unused-function",
    "-Wno-unused-variable",
    "-Wno-unused-parameter"
]

let whisperCSettings = whisperDefines + [
    .unsafeFlags(nativeWarningSuppressions, .when(platforms: [.macOS]))
]

let whisperCXXSettings = whisperCXXDefines + [
    .unsafeFlags(nativeWarningSuppressions, .when(platforms: [.macOS]))
]

let whisperShimCSettings: [CSetting] = [
    .headerSearchPath("include")
]

let whisperShimCXXSettings: [CXXSetting] = [
    .headerSearchPath("include")
]

let whisperLinkerSettings: [LinkerSetting] = [
    .linkedFramework("Accelerate", .when(platforms: [.macOS])),
    .linkedFramework("Metal", .when(platforms: [.macOS])),
    .linkedFramework("Foundation", .when(platforms: [.macOS])),
    .linkedLibrary("c++", .when(platforms: [.macOS]))
]
```

Unsafe flags policy: only warning suppressions are allowed. Do not use unsafe `-I`, `-L`, `-framework`, architecture, Core ML, or optimization flags.

Until the vendored source is present, keep Task 7 mock provider as the default runtime.

- [ ] **Step 2: Vendor pinned upstream snapshot**

`Vendor/whisper.cpp/UPSTREAM.md` must contain:

```markdown
# whisper.cpp Upstream Snapshot

Upstream repository: https://github.com/ggml-org/whisper.cpp
Commit SHA: write the full 40-character upstream commit SHA selected during this task
Tag: write the upstream tag when the selected commit is tagged; otherwise write none
Date copied: write the ISO date when the snapshot is copied
Included paths:
- include/
- src/
- ggml/
Excluded paths:
- examples/
- bindings/
- models/
- samples/
- tests/
- server examples
- benchmark tools
Local patches:
- none
```

A completed `UPSTREAM.md` must contain the real full commit SHA, not a branch
name, short SHA, or prose description.

Require this layout:

```text
Vendor/whisper.cpp/
  UPSTREAM.md
  README.TEXTIFY.md
  LICENSE
  include/whisper.h
  src/whisper.cpp
  src/whisper-arch.h
  ggml/include/*.h
  ggml/src/ggml*.c
  ggml/src/ggml*.cpp
  ggml/src/ggml-cpu/
  ggml/src/ggml-metal/
  spm/include/TextifyWhisperVendor.h
  spm/include/module.modulemap

Sources/TextifyWhisperShim/
  include/TextifyWhisperShim.h
  include/module.modulemap
  TextifyWhisperShim.mm
```

`Vendor/whisper.cpp/spm/include/module.modulemap`:

```c
module WhisperCppVendor [system] {
  header "TextifyWhisperVendor.h"
  export *
}
```

`Vendor/whisper.cpp/spm/include/TextifyWhisperVendor.h`:

```c
#pragma once
#include "whisper.h"
```

- [ ] **Step 3: Add shim boundary**

Expose only C-compatible functions needed by Swift:

```c
#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TextifyWhisperContext TextifyWhisperContext;

TextifyWhisperContext *textify_whisper_load(const char *model_path, int32_t use_gpu, int32_t thread_count);
void textify_whisper_free(TextifyWhisperContext *context);

int32_t textify_whisper_transcribe(
    TextifyWhisperContext *context,
    const float *pcm_mono_f32_16khz,
    int32_t sample_count
);

const char *textify_whisper_last_text(TextifyWhisperContext *context);
const char *textify_whisper_last_error(TextifyWhisperContext *context);

int32_t textify_whisper_compiled_with_metal(void);
int32_t textify_whisper_compiled_with_coreml(void);

#ifdef __cplusplus
}
#endif
```

`Sources/TextifyWhisperShim/include/module.modulemap`:

```c
module TextifyWhisperShim {
  header "TextifyWhisperShim.h"
  export *
}
```

- [ ] **Step 4: Implement Swift actor wrapper**

`WhisperRuntime` owns:

- loaded context
- active model id
- load/warmup/unload/switch
- serial dispatch queue for blocking native inference
- in-flight task waiting before switch/unload

Add native boundary tests that assert:

- `textify_whisper_compiled_with_metal() == 1`
- `textify_whisper_compiled_with_coreml() == 0`
- loading a missing model path fails with a non-empty last error

- [ ] **Step 5: Verify**

```bash
swift package describe --type json
swift build -c release --arch arm64
swift test
if rg -n "WHISPER_USE_COREML|CoreML|\\.mlmodelc|coreml" Package.swift Vendor/whisper.cpp Sources; then
  exit 1
fi
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Textify"
otool -L "$BIN" | rg "Accelerate|Metal|Foundation|libc\\+\\+"
```

Expected: release build succeeds on Apple Silicon, Core ML is absent, and the final binary links the expected Apple frameworks/libraries. Manual smoke with a real model is recorded in `docs/implementation/coordination.md`.

If Task 14 has already merged, also run:

```bash
./script/generate_xcode_project.sh
xcodebuild -project Textify.xcodeproj -scheme Textify -configuration Release -destination 'generic/platform=macOS' build
```

- [ ] **Step 6: Commit**

```bash
git add Package.swift Vendor Sources/TextifyWhisperShim Sources/TextifyTranscription/Native THIRD_PARTY_NOTICES.md ACKNOWLEDGMENTS.md docs/implementation/coordination.md
git commit -m "task-13: add native whisper runtime"
```

## Task 14: Xcode Bundle And Distribution Scaffold

**Files:**

- Create: `project.yml`
- Create: `script/generate_xcode_project.sh`
- Create: `Resources/Info.plist`
- Create: `Resources/Assets.xcassets/Contents.json`
- Create: `Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `Textify.xcodeproj/`
- Create: `Textify.entitlements`
- Create: `docs/RELEASING.md`
- Create: `docs/MANUAL_QA.md`
- Modify: `script/build_and_run.sh`

Do not hand-author `Textify.xcodeproj/project.pbxproj`. `project.yml` is the source of truth. Regenerate the Xcode project with `script/generate_xcode_project.sh`, then commit the generated `Textify.xcodeproj/`.

- [ ] **Step 1: Create bundle metadata**

`Resources/Info.plist` must include:

- `CFBundleExecutable`: `Textify`
- `CFBundleIdentifier`: `io.github.Player0109.Textify`
- `CFBundleName`: `Textify`
- `CFBundlePackageType`: `APPL`
- `CFBundleShortVersionString`: `0.1.0`
- `CFBundleVersion`: `1`
- `LSMinimumSystemVersion`: `14.0`
- `LSUIElement`: `true`
- `NSPrincipalClass`: `NSApplication`
- `NSMicrophoneUsageDescription`: `Textify uses your microphone to transcribe speech while you're actively dictating. Audio is processed on-device and never leaves your Mac.`
- `NSHumanReadableCopyright`

- [ ] **Step 2: Create entitlements file**

Initial `Textify.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
```

Do not add App Sandbox.

- [ ] **Step 3: Create reproducible Xcode project spec**

`script/generate_xcode_project.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

command -v xcodegen >/dev/null || {
  echo "xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 127
}

xcodegen generate --spec project.yml
```

`project.yml`:

```yaml
name: Textify

options:
  minimumXcodeGenVersion: 2.42.0
  createIntermediateGroups: true
  deploymentTarget:
    macOS: "14.0"

packages:
  TextifyPackage:
    path: .

targets:
  Textify:
    type: application
    platform: macOS
    deploymentTarget: "14.0"

    sources:
      - path: Sources/Textify
      - path: Resources/Assets.xcassets

    dependencies:
      - package: TextifyPackage
        product: TextifyCore
      - package: TextifyPackage
        product: TextifyAudio
      - package: TextifyPackage
        product: TextifyTranscription
      - package: TextifyPackage
        product: TextifyModels
      - package: TextifyPackage
        product: TextifyInsertion
      - package: TextifyPackage
        product: TextifyHotkeys
      - package: TextifyPackage
        product: TextifyDiagnostics
      - package: TextifyPackage
        product: TextifySettings

    settings:
      base:
        PRODUCT_NAME: Textify
        PRODUCT_BUNDLE_IDENTIFIER: io.github.Player0109.Textify
        INFOPLIST_FILE: Resources/Info.plist
        GENERATE_INFOPLIST_FILE: NO
        CODE_SIGN_ENTITLEMENTS: Textify.entitlements
        CODE_SIGN_STYLE: Manual
        CODE_SIGN_IDENTITY: "-"
        DEVELOPMENT_TEAM: ""
        ENABLE_HARDENED_RUNTIME: YES
        MACOSX_DEPLOYMENT_TARGET: "14.0"
        SWIFT_VERSION: "5.9"
        ARCHS: arm64
        SUPPORTED_PLATFORMS: macosx
        SDKROOT: macosx
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        CURRENT_PROJECT_VERSION: "1"
        MARKETING_VERSION: "0.1.0"
      configs:
        Debug:
          ONLY_ACTIVE_ARCH: YES
        Release:
          ONLY_ACTIVE_ARCH: NO

schemes:
  Textify:
    build:
      targets:
        Textify: all
    run:
      config: Debug
    archive:
      config: Release
```

The Xcode project depends on SwiftPM package products only. Do not add `WhisperCppVendor`, `TextifyWhisperShim`, or vendored whisper.cpp files directly to the app target unless app source imports the shim directly. Native flags stay only in `Package.swift`.

- [ ] **Step 4: Update run script**

Keep the default `script/build_and_run.sh` path as the SwiftPM-staged `.app` fast path. After `Resources/Info.plist` exists, update the fast path to copy that plist into `dist/Textify.app/Contents/Info.plist` instead of maintaining duplicate bundle metadata inline.

Add `--full` mode and update the script usage text to include it:

```bash
./script/generate_xcode_project.sh
xcodebuild -project Textify.xcodeproj -scheme Textify -configuration Debug -destination 'platform=macOS' -derivedDataPath dist/DerivedData build
/usr/bin/open -n dist/DerivedData/Build/Products/Debug/Textify.app
```

- [ ] **Step 5: Verify**

```bash
swift test
chmod +x script/generate_xcode_project.sh
./script/generate_xcode_project.sh
xcodebuild -list -project Textify.xcodeproj
xcodebuild -resolvePackageDependencies -project Textify.xcodeproj -scheme Textify
xcodebuild -project Textify.xcodeproj -scheme Textify -configuration Debug -destination 'platform=macOS' -derivedDataPath dist/DerivedData build
xcodebuild -project Textify.xcodeproj -scheme Textify -configuration Release -destination 'generic/platform=macOS' -archivePath dist/archive/Textify.xcarchive archive
./script/build_and_run.sh --full
```

Expected: SwiftPM tests pass, the generated project lists the `Textify` scheme, Debug builds as an app bundle, Release archives to `dist/archive/Textify.xcarchive`, and `--full` launches the Xcode-built app bundle.

- [ ] **Step 6: Commit**

```bash
git add project.yml script/generate_xcode_project.sh Textify.xcodeproj Resources Textify.entitlements docs/RELEASING.md docs/MANUAL_QA.md script/build_and_run.sh
git commit -m "task-14: add Xcode bundle scaffold"
```

## Task 15: End-To-End Mock Integration

**Files:**

- Modify: `Sources/Textify/App/AppServices.swift`
- Modify: `Sources/Textify/UI/MenuBarRoot.swift`
- Modify: `Sources/Textify/Onboarding/OnboardingRootView.swift`
- Modify: `Sources/Textify/SettingsUI/SettingsRootView.swift`
- Modify: `Sources/TextifyCore/Dictation/DictationController.swift`
- Modify: `docs/implementation/coordination.md`

- [ ] **Step 1: Wire services**

Create `AppServices` that owns:

- settings store
- diagnostics logger
- model catalog state
- mock transcription provider
- fake insertion service for SwiftPM run
- dictation controller

- [ ] **Step 2: Add mock dictation command**

The menu bar UI may include a development-only action named `Run Mock Dictation` while native hotkeys are still being integrated. This action must be compiled out or hidden before V1 release.

- [ ] **Step 3: Verify mock loop**

Run:

```bash
./script/build_and_run.sh --verify
```

Manual proof:

- app launches
- Settings opens
- onboarding can be shown
- mock dictation flows through state machine
- diagnostics writes no dictated content

Record the proof in `docs/implementation/coordination.md`.

- [ ] **Step 4: Full test**

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Textify Sources/TextifyCore docs/implementation/coordination.md
git commit -m "task-15: integrate mock dictation path"
```

## Merge Gates

Gate A after Task 1:

```bash
swift build
swift test
./script/build_and_run.sh --verify
```

Gate B after Wave 1 tasks 2 through 7:

```bash
swift test --filter TextifyCoreTests
swift test --filter TextifyDiagnosticsTests
swift test --filter TextifyModelsTests
swift test --filter TextifySettingsTests
swift test --filter TextifyAudioTests
swift test --filter TextifyTranscriptionTests
swift test
```

Gate C after Wave 2 tasks 8 through 10:

```bash
swift test --filter DictationControllerTests
swift test --filter TextifyInsertionTests
swift test --filter TextifyHotkeysTests
swift test
```

Gate D after Task 11:

```bash
swift build
swift test
./script/build_and_run.sh --verify
```

Gate E before native/release work:

```bash
swift test
./script/build_and_run.sh --verify
```

## Parallel Agent Assignment

After Task 1 merges:

- Agent Core: Task 2
- Agent Diagnostics: Task 3
- Agent Models: Task 4
- Agent Settings: Task 5
- Agent Audio: Task 6
- Agent Transcription: Task 7

After Wave 1 merges:

- Agent Orchestrator: Task 8
- Agent Insertion: Task 9
- Agent Hotkeys: Task 10

After Wave 2 merges:

- Agent UI: Task 11
- Agent Downloads: Task 12

After Wave 3 merges, run Wave 4 serially:

- Agent Native Runtime: Task 13

After Task 13 merges:

- Agent Bundle: Task 14

After Task 14 merges:

- Agent Integration: Task 15

## Self-Review

Spec coverage:

- Product loop is covered by Tasks 7, 8, 9, 10, 11, and 15.
- Text processing is covered by Task 2.
- Privacy diagnostics are covered by Task 3.
- Model manifest, downloads, and runtime are covered by Tasks 4, 12, and 13.
- Settings, onboarding, menu bar app, and Launch at Login UI surfaces are covered by Tasks 5, 11, and 14.
- Audio capture pure logic is covered by Task 6; AVAudioEngine live capture is introduced after the pure detector passes.
- Xcode, entitlements, and release packaging are covered by Task 14.

Deferred to milestone:

- Exact whisper.cpp upstream commit is chosen in Task 13.
- Final model hashes and GitHub release asset URLs are produced in Task 12 when mirrored assets exist.
- Sparkle private key, notarization credentials, and signed DMG flow are handled after Task 14.
- App icon asset is added with `Resources/Assets.xcassets` in Task 14 or by a dedicated visual asset task before release.

No task may claim release readiness until the manual QA list in `docs/SPEC.md` section 28 passes.
