# Textify V1 Spec

Snapshot date: 2026-07-03

This document captures the Textify V1 product and technical decisions from the
grill session through Q350. It is a current-state decision snapshot, not a public
roadmap. Items listed as out of scope are boundaries for V1, not commitments for
future versions.

### Current V1.1 release profile

The shipping target began with the narrower V1.1 implementation plan in
`docs/superpowers/plans/2026-07-03-textify-v1-parallel-implementation.md`.
The production hardening and multi-model workstream recorded in
`docs/implementation/coordination.md` now supersedes that plan's single-model,
Whisper-only, and no-Core-ML boundaries. Textify remains arm64-only, uses the
system-default microphone, and is distributed as a manually updated GitHub
Release DMG. It now supports a signed multi-model catalog, multiple installed
models, safe switching/deletion, verified custom Whisper import, Whisper on
Metal, and released FluidAudio batch engines on Core ML/Apple Neural Engine.
It still omits Sparkle, history, vocabulary/custom words, per-app profiles,
cloud ASR, and live partial transcription. The trigger is user-selectable from
the four curated choices, with Right Command as the default. A runtime is not a
public model promise until its exact artifacts and metadata are published in
the signed catalog.

Last external grill respondent:

- Claude session used through Q329: `02de4aa5-d168-4f20-a2dc-e9ffd8afa33c`
- Codex session used from Q330 onward: `019f25f5-3ff3-7571-9137-d5ecfbfaaba4`
- Last completed grill question: Q350

## 1. Product Summary

Textify is a native macOS hybrid Dock and menu-bar dictation utility.

Core V1 loop:

1. User holds the configured trigger, defaulting to Right Command.
2. Textify records speech while the trigger is held.
3. User releases the trigger.
4. Textify transcribes locally.
5. Textify post-processes the text.
6. Textify inserts the final text into the current app.

V1 is a global dictation app, not a long-form transcription workspace.

V1 optimizes for short, fast dictation:

- One sentence to one paragraph is the primary path.
- Max recording duration defaults to about 60 seconds.
- Long-form transcription, file transcription, and streaming partial captions are out of scope.

The app should feel like a quiet system utility with a dependable home:

- Dock icon by default so Textify is easy to reopen.
- Menu bar icon always visible.
- One persistent main window for setup, status, and settings.
- Minimal overlay while recording.
- No confirmation UI before insertion.
- Normal successful dictation should disappear visually as soon as possible.

## 2. Product Principles

These principles should guide future unresolved decisions:

- Prefer native Apple frameworks unless there is a real capability gap.
- Keep settings minimal; do not expose implementation knobs without a clear user trade-off.
- Prefer fixed, deterministic behavior in V1 over broad configurability.
- Surface only actionable problems.
- Stay silent for benign no-ops.
- Avoid storing dictated content.
- Do not add per-app behavior unless V1 explicitly requires it.
- Keep the runtime offline after setup.
- Treat user-facing trust claims as implementation requirements.
- Prefer simple, inspectable formats such as JSON and JSONL.
- Let release-blocking manual QA cover OS permission and cross-app behavior that CI cannot test.

## 3. Naming, License, Repo Policy

- Product name: Textify
- Repo name: Textify
- Bundle identifier: `io.github.Player0109.Textify`
- License: Apache-2.0
- External contribution policy for V1: issues only
- External pull requests: not accepted initially; close without review
- Public roadmap: none
- Internal decision artifact: `docs/SPEC.md`

Public repo docs planned from initial scaffold:

- `README.md`
- `LICENSE`
- `CHANGELOG.md`
- `PRIVACY.md`
- `ACKNOWLEDGMENTS.md`
- `THIRD_PARTY_NOTICES.md`
- `THIRD_PARTY_LICENSES/`
- `.github/CONTRIBUTING.md`
- `.github/SECURITY.md`
- `.github/ISSUE_TEMPLATE/bug_report.yml`
- `.github/ISSUE_TEMPLATE/feature_request.yml`
- `.github/ISSUE_TEMPLATE/model_suggestion.yml`
- `.github/ISSUE_TEMPLATE/config.yml`
- `docs/SPEC.md`
- `docs/RELEASING.md`
- `docs/MANUAL_QA.md`
- `docs/models/curated-models.md`
- `AGENTS.md`

`CODE_OF_CONDUCT.md` and a full ADR directory are deferred for V1.

## 4. Platform And Distribution

V1 platform:

- macOS 14 Sonoma or later
- Apple Silicon only
- Arm64-only builds
- Intel Macs are not supported in V1

Distribution:

- Direct download first
- Signed, notarized, stapled DMG
- No Mac App Store V1
- No PKG installer V1
- No separate ZIP artifact V1

Compatibility wording in README/releases:

> macOS 14 (Sonoma) or later, Apple Silicon (M1 or later). Intel Macs are not supported.

Release artifact naming should include architecture, for example:

- `Textify-1.0.0-arm64.dmg`

V1 hosting uses GitHub-owned project infrastructure only:

- Signed/notarized DMG releases:
  `https://github.com/Player0109/Textify/releases/download/v1.0.0/Textify-1.0.0-arm64.dmg`
- Sparkle appcast:
  `https://player0109.github.io/Textify/appcast.xml`
- Signed remote model manifest:
  `https://player0109.github.io/Textify/models/manifest.json`
  and `https://player0109.github.io/Textify/models/manifest.json.sig`
- Model files:
  immutable Textify GitHub Release assets, for example
  `https://github.com/Player0109/Textify/releases/download/models-v1/ggml-small.en-q5_1.bin`
  or exact commit-pinned Hugging Face files, for example
  `https://huggingface.co/<owner>/<repo>/resolve/<40-character-lowercase-commit>/<file>`

Reason: Textify curates exact model bytes rather than trusting a mutable model
name. Every signed file record binds an immutable approved URL, exact byte size,
and SHA-256 together with upstream license and provenance. Hugging Face branch
or tag URLs such as `resolve/main` are never accepted.

## 5. Signing, Notarization, Entitlements

Textify is non-sandboxed in V1.

Reason: core functionality depends on global keyboard observation, Accessibility
insertion, and cross-app event posting. Sandboxing would severely restrict or
break this behavior.

Hardened Runtime:

- Enabled for distribution with `codesign --options runtime`.
- Do not add Hardened Runtime exception entitlements unless a verified build
  failure proves they are required.
- Do not disable library validation for Sparkle. Re-sign embedded Sparkle code
  correctly in the release build.

Info.plist requirements:

- `CFBundleIdentifier`: `io.github.Player0109.Textify`
- `CFBundleShortVersionString`
- `CFBundleVersion`
- `LSMinimumSystemVersion`: `14.0`
- `LSUIElement`: `true`
- App icon asset reference
- `NSHumanReadableCopyright`
- `NSMicrophoneUsageDescription`

Recommended microphone usage text:

> Textify uses your microphone to transcribe speech while you're actively dictating. Audio is processed on-device and never leaves your Mac.

No usage description key exists for Accessibility or AppKit keyboard event
monitoring.

`NSAppleEventsUsageDescription` is not needed because V1 does not use Apple
Events automation.

Release key management:

- Developer ID certificate private keys and notary credentials stay in the
  maintainer's local Keychain/account only.
- Sparkle update signing uses its own Ed25519 keypair.
- The Sparkle private key stays in local encrypted/offline storage only.
- `SUPublicEDKey` is public and is stored in the app `Info.plist`, repo, and
  release docs.
- Model manifest signing uses a separate Ed25519 keypair.
- Model manifest private keys stay in local encrypted/offline storage only.
- Model manifest public keys and `keyId` values are public and are stored in
  app resources/source, repo, and release docs.

Never commit:

- Apple `.p12` files or private certs
- certificate passwords
- notary credentials or API keys
- Sparkle private key exports
- model-manifest private keys
- recovery keys
- signing environment files

GitHub Actions may build and test unsigned artifacts in V1.

Final release signing, notarization, Sparkle appcast signing, and model-manifest
signing are manual maintainer-machine operations in V1. GitHub hosts public
outputs but does not hold V1 signing authority.

Minimum rotation story:

- Sparkle key rotation happens through a Developer ID-signed DMG update that
  embeds the new Sparkle public key.
- Do not rotate Developer ID and Sparkle signing material in the same update
  unless unavoidable.
- Model manifest signatures include a `keyId`.
- V1 app supports a small embedded trusted public-key set, normally active key
  plus one reserve key.
- If the active model key is lost, sign with reserve, then ship an app update
  that installs a new active/reserve set.
- If a private key is suspected compromised, stop publishing the affected feed
  or manifest, publish a GitHub security notice, rotate through a signed app
  update if still trustworthy, otherwise require manual download of a fresh
  notarized DMG.

## 6. App Update Policy

V1 uses Sparkle for direct-distributed app updates.

Policy:

- Signed Sparkle appcast.
- Automatic update checks.
- Manual "Check for Updates..." action.
- Installation always requires explicit user approval.
- No silent app replacement.
- Sparkle optional system profile sending must be disabled to match privacy claims.

General settings update controls:

- Automatically check for updates
- Check for Updates Now
- App version display

Sparkle signing keys are not stored in GitHub Actions for V1.

## 7. Build Strategy

The project is SwiftPM-first for source structure and ordinary logic tests.

However, V1 also includes a thin Xcode project for real `.app` bundling,
assets, entitlements, Sparkle embedding, signing, archiving, notarization, and
release.

SwiftPM package:

- Owns all real application logic.
- Contains internal library targets and tests.
- Is used for day-to-day `swift build` and `swift test`.

Thin Xcode project:

- Owns bundle assembly and release packaging.
- Contains near-zero app logic.
- Used by `xcodebuild` for full local app runs and local release archiving.

Local run script:

- `script/build_and_run.sh`
- Default fast mode:
  - `swift build`
  - stage a lightweight `.app`
  - ad-hoc sign with `codesign --sign -`
  - suitable for UI/logic iteration only
- Full mode:
  - `script/build_and_run.sh --full`
  - builds through Xcode
  - supported path for testing TCC-gated behavior

Codex environment:

- Default Run action invokes fast mode.
- Optional secondary action invokes `--full`.

## 8. Repository Documentation

README structure:

1. Title and factual tagline
2. Badges
3. What it does
4. Requirements
5. Installation
6. Getting started
7. Models
8. Privacy
9. Contributing
10. License
11. Acknowledgments

README language should be factual:

- Do not compare against competitors.
- Do not use roadmap language.
- State English-only and Apple-Silicon-only constraints clearly.
- Use verifiable claims instead of marketing adjectives.

README model wording:

> Textify does not bundle speech model binaries. During onboarding, Textify can
> download curated model files from immutable Textify GitHub Release assets or
> exact commit-pinned public Hugging Face files. Whisper was developed and
> released by OpenAI, Parakeet by NVIDIA, and Paraformer by the FunASR ecosystem.
> Exact source links, revisions, licenses, byte sizes, checksums, and provenance are listed in
> `ACKNOWLEDGMENTS.md`, `THIRD_PARTY_NOTICES.md`, and the signed model manifest.

Also state:

> Model suggestions are accepted through GitHub issues only. Textify does not
> accept model binary pull requests.

`PRIVACY.md` claims:

- Audio and dictated text never leave the Mac.
- Audio is captured only while actively dictating.
- Audio is processed in memory and never saved by default.
- No dictation history.
- No analytics.
- No crash reporting.
- No accounts.
- No servers that see dictated content.
- Network is used for app update checks and curated model downloads.
- Model/update hosts may see ordinary request metadata such as IP address.
- Textify does not send extra analytics or system profiles with those requests.
- Clipboard insertion briefly writes dictated text to the system clipboard, marks
  it transient/concealed on a best-effort basis, and restores the previous
  clipboard.
- The transient/concealed clipboard behavior is a best-effort convention, not a
  guarantee against all clipboard managers.
- Diagnostics exports are explicit and contain only technical metadata.
- Vocabulary, custom words, excluded apps, and settings remain local.

`SECURITY.md`:

- Use GitHub private vulnerability reporting.
- Public issues should not contain exploit details.
- Acknowledge reports within about 5 business days.
- No fixed remediation SLA.
- In scope: Accessibility/keyboard-monitoring paths, insertion, model downloads,
  manifest verification, Sparkle, signing/notarization, vendored dependencies.
- Out of scope: documented punctuation command collisions and best-effort
  clipboard transient marking.

`CONTRIBUTING.md`:

- Lead with "Textify does not accept external pull requests at this time."
- All contributions happen through GitHub Issues.
- Bug reports, feature requests, and model suggestions are welcome.
- Model suggestions do not guarantee inclusion.
- Pull requests opened against the repo are closed without review.
- Security reports go through `SECURITY.md`.

## 9. GitHub Issues

Use YAML Issue Forms.

Disable blank issues.

Templates:

- Bug Report
- Feature Request
- Model Suggestion

Bug report fields:

- Textify version
- macOS version
- Mac model/chip
- Model tier
- Trigger in use
- Target app dropdown, if relevant
- Frequency
- What happened
- What expected
- Steps to reproduce
- Diagnostics export attachment checkbox/note

Target app field should be a dropdown with a narrow "Other" field:

- Not applicable
- TextEdit
- Notes
- Mail
- Safari
- Chrome
- Slack
- Messages
- Terminal
- VS Code
- Pages
- Microsoft Word
- Other

Free-text target app fallback must say:

> App name only. Do not include window titles, document names, URLs, or dictated text.

Bug templates must ask users not to paste dictated text.

Model suggestion template:

- Model name
- Source URL
- License
- Approximate size
- Why it should be added
- Whether it was tested with whisper.cpp

Top disclaimer:

> Model suggestions are reviewed by maintainers and added at their discretion based on license compatibility, quality, and fit. Filing this issue does not guarantee inclusion or a timeline.

## 10. App Shape

Textify is a hybrid Dock and menu-bar utility.

Default behavior:

- Dock icon is visible.
- After onboarding, an ordinary launch opens the main Textify window.
- Menu bar icon always visible.
- The existing Settings `TabView` is the main Textify window; do not create a
  second settings surface.
- Closing the main window keeps Textify running for menu-bar dictation.
- Only an explicit Quit action terminates Textify.
- Clicking the Dock icon opens or focuses the same main window.
- The first menu-bar action, "Open Textify…", opens or focuses that window.
- Onboarding opens only on fresh install or reset.

Keep Textify in the Dock:

- General setting.
- Default on.
- Requires relaunch.
- Persist preference immediately.
- Persist new choices under `keepTextifyInDock`.
- Legacy settings stored under `showInDock` migrate once to the new Dock-on
  default because the legacy format did not distinguish its old default from
  an explicit opt-out.
- Users may opt out after migration; the menu-bar Open Textify action remains
  the dependable reopen path in accessory mode.
- Apply activation policy at next launch only.
- Do not switch activation policy live mid-session.

Launch sequencing:

- `LSUIElement=true` in Info.plist.
- In `applicationWillFinishLaunching`, set activation policy early based on
  Keep Textify in the Dock preference.
- If regular Dock mode is enabled, implement Dock reopen handling:
  - Clicking Dock icon with no windows opens the main window.
  - Clicking Dock icon with a visible main window focuses it.
- If a window appears at launch, activate the app explicitly.

Launch at Login:

- General setting and onboarding completion checkbox.
- Default checked during onboarding final screen.
- Implement with `SMAppService.mainApp`.
- Register only when user taps Done with the box checked.
- If `.requiresApproval`, show non-blocking note with System Settings link.
- Toggle reflects live OS status, not cached preference.
- Do not register if onboarding is interrupted before Done.
- Settings toggle calls `SMAppService.mainApp.register()` when enabling.
- Settings toggle calls `SMAppService.mainApp.unregister()` when disabling.
- Refresh `SMAppService.mainApp.status` immediately after register/unregister.
- Allow enabling only when Textify is in `/Applications` or `~/Applications`.
- If running from Downloads, a mounted DMG, or another unsupported path,
  disable the toggle and show "Move Textify to Applications to use Launch at
  Login."

Launch at Login status mapping:

| Status | Settings state | Message |
| --- | --- | --- |
| `.enabled` | Toggle on | "Textify will open at login." |
| `.notRegistered` | Toggle off | "Textify will not open at login." |
| `.requiresApproval` | Toggle off + warning | "macOS needs approval before Textify can open at login." |
| `.notFound` | Toggle off disabled | "Textify is not in a supported location for Launch at Login." |
| error/unknown | Toggle off + retry | "Textify could not check Launch at Login status." |

For `.requiresApproval`:

- Do not block onboarding completion.
- Show Open Login Items Settings.
- Do not repeatedly call `register()` in the background.
- User must approve in System Settings -> General -> Login Items.

If unregister fails, refresh status and show "Textify could not disable Launch
at Login. Use System Settings -> General -> Login Items."

Login launch behavior:

- If launched at login and onboarding is complete, start the runtime and show
  the main window using the same launch path as an ordinary app launch.
- If onboarding is incomplete or was reset, show onboarding.
- `LSUIElement` remains in the bundle metadata; the early activation policy
  shows the Dock icon unless Keep Textify in the Dock is disabled.

Launch at Login diagnostics may include:

```json
{
  "event": "launch_at_login_change",
  "requestedAction": "enable",
  "statusBefore": "notRegistered",
  "statusAfter": "requiresApproval",
  "appLocationCategory": "applications",
  "succeeded": false,
  "errorDomain": null,
  "errorCode": null
}
```

Do not log full app paths, usernames, Apple IDs, device names, or file system
locations.

## 11. Menu Bar Menu

Menu bar icon:

- Always visible.
- Monochrome template icon.
- Does not show readiness badges or warning colors.
- May subtly change only while actively recording.

Menu dropdown:

```text
[Open Textify…]
[optional status lines]
Check for Updates...
About Textify
Quit Textify
```

Status line rules:

- At most two lines.
- Permissions line:
  - shown if any required permission is missing or revoked
  - collapsed across Microphone and Accessibility
  - opens Settings -> Privacy
- Model line:
  - shown if no model is installed/ready or a model is downloading
  - opens Settings -> Models
- Permissions line appears above Model line.
- No "Ready" line.
- No persistent transient dictation errors.

Excluded from menu:

- Start Dictation
- Model quick switcher
- Diagnostics actions
- Privacy actions
- Excluded app contextual status
- Transcript snippets or history

## 12. Standard App Menus

When Textify is active, keep normal macOS menus.

App menu:

- About Textify
- Open Textify…
- Hide Textify
- Hide Others
- Show All
- Quit Textify

Edit menu:

- Undo
- Redo
- Cut
- Copy
- Paste
- Delete
- Select All

Window menu:

- Minimize
- Zoom
- Bring All to Front

Help menu:

- Textify Help, linking to README

No File or View menu content for V1.

## 13. Main Window And Settings

Use one AppKit-managed window hosting the SwiftUI `SettingsRootView` `TabView`.
The presenter retains that window after close so every open route reuses it.

Panes:

- General
- Dictation
- Models
- Vocabulary
- Privacy
- Advanced

Use Swift Observation (`@Observable`) rather than `ObservableObject`.

Settings pane routing:

- Shared `@Observable` `SettingsRouter`.
- `selectedPane` bound to `TabView(selection:)`.
- SwiftUI, menu, launch, and Dock callers set router state as needed and call
  the shared main-window presenter.

### 13.1 General

Controls:

- Launch at Login
- Keep Textify in the Dock
- Automatically check for updates
- Check for Updates Now
- App version

Excluded:

- Trigger selection
- Model selection
- Vocabulary
- Excluded apps
- Diagnostics export
- Cleanup intensity
- Appearance/theme
- Overlay customization
- Metal/thread tuning

### 13.2 Dictation

Controls:

- Dictation Trigger
- Microphone
- Test Trigger

Microphone control:

- Default value: System Default.
- Explicit selection stores CoreAudio device UID plus last-seen display name.
- UI list shows System Default first, then available input devices.
- Missing explicitly selected devices show as Unavailable.
- Show a simple live input level meter in onboarding and Settings -> Dictation.
- Level meter is active only while that UI is visible.
- Level meter keeps no recording, waveform history, or retained audio.
- If microphone permission is missing, show the permission action instead of
  the meter.

No spoken-punctuation toggle.

No filler cleanup toggle.

No language selector in V1.

No insertion method selector.

No overlay customization.

### 13.3 Models

Models pane shows curated entries from the active manifest source.

Rows show:

- Tier
- Display name
- Actual model name
- Description
- Download size
- Installed size
- License
- Source link
- Current state

States:

- Not installed: Download button
- Downloading: progress and Cancel
- Installed, not active: Set Active and Delete
- Installed, active: Active badge and Delete
- Deprecated installed model: "No longer in curated list" badge

First installed model auto-activates.

Subsequent installed models do not auto-switch.

Deleting active model requires confirmation:

> This is your active dictation model. Deleting it will leave Textify unable to dictate until you install another. Delete anyway?

If no model is installed, show a banner:

> No model installed. Download one to start dictating.

Manifest refresh:

- Fetch silently when Models pane opens.
- Manual Refresh button.
- Fetch failure falls back to cached/built-in manifest.

### 13.4 Vocabulary

Vocabulary has two subsections.

Custom Words:

- Single-column list.
- Add/remove.
- Helps recognition using whisper.cpp `initial_prompt`.
- Not guaranteed.
- Contents are never logged.

Replacement Pairs:

- Two-column table:
  - "When I say"
  - "Replace with"
- Add/remove.
- Inline editing.
- Case-insensitive trigger matching.
- Replacement inserted exactly as typed.
- Whole word/phrase boundary matching.
- Multi-word phrases supported.
- Longest match first.
- No regex.
- No wildcards.
- Duplicate triggers blocked.
- Empty trigger or replacement blocked.
- Warn when trigger conflicts with reserved command phrases.
- Replacement output is literal final text; command words inside replacements
  are never reinterpreted.
- Replacement output can contain literal newlines.
- Replacement spans are protected from later whitespace/capitalization changes.

Internal representation:

```swift
enum TextSegment {
    case mutable(String)
    case protected(String)
}
```

`TextSegment` exists only between replacement and final formatting stages.

### 13.5 Privacy

Sections:

- Permissions
- Excluded Apps
- Audio and Data Retention
- Diagnostics
- Privacy Statement

Permissions:

- Microphone
- Accessibility

Show status and System Settings links. Do not fake toggles.

Excluded Apps:

- List icon and name.
- User-managed list starts empty.
- No built-in/default excluded apps in V1.
- No non-removable exclusions in V1.
- Add via running app picker.
- Add via `.app` open panel.
- Drag-and-drop app support if cheap.
- Remove entry.
- Empty state: "No excluded apps."
- Actions include Add Current App and Remove.
- Rows show app name and bundle ID.
- Missing apps show Unavailable but remain removable.

Excluded app identity:

```json
{
  "bundleIdentifier": "...",
  "displayName": "...",
  "cachedIconData": "...",
  "lastKnownPath": "..."
}
```

Bundle ID is authoritative.

Missing apps stay listed as Not Installed. Do not auto-delete them.

Do not prepopulate exclusions for password managers, System Settings, Terminal,
browsers, developer tools, TextEdit, Notes, mail apps, or similar apps.

Reason: whole-app exclusions are too blunt. Sensitive entry is handled by the
positive secure/password-field Accessibility check. Default app blacklists would
create surprising "Textify does nothing here" behavior and require constant
bundle ID maintenance.

Audio/Data statement:

- Dictated audio is processed in memory.
- Dictated audio is not saved.
- No dictation history is kept.

Diagnostics:

- Export Diagnostics...
- Clear Diagnostics Log
- Explain diagnostics contain technical metadata and no dictated text.

Privacy statement:

- Textify runs offline for dictation.
- No analytics.
- No crash reporting.
- No accounts.
- No servers.
- View Source on GitHub link.

### 13.6 Advanced

Controls:

- Reset Onboarding
- Reset All Settings
- Open Diagnostics Folder
- Runtime Status
- Developer Mode

Reset Onboarding:

- Clears onboarding-completion state.
- Clears one-time notice flags.
- Does not delete models, vocabulary, excluded apps, or settings.
- Does not change Launch at Login.

Reset All Settings:

- Requires confirmation.
- Clears vocabulary, custom words, excluded apps, preferences.
- Does not delete downloaded models.
- Calls `SMAppService.mainApp.unregister()` and refreshes status.
- If unregister fails, show the System Settings fallback message.

Runtime Status:

- Active runtime
- Metal acceleration enabled/disabled
- Thread count in use

Developer Mode:

- Exists in release builds.
- Hidden under Advanced.
- Off by default.
- Safe by default.

Developer Mode enables:

- Read-only recent runtime metrics.
- Optional separate Verbose Diagnostics toggle.
- Copy Diagnostic Info action.

Developer Mode never enables:

- Threshold editing.
- Mock provider in release.
- Subprocess provider in release.
- Transcript logging.
- Custom Words logging.
- Vocabulary contents logging.

## 14. Onboarding

Final onboarding order:

1. Welcome
2. Model tier selection
3. Microphone permission
4. Accessibility permission
5. Trigger/test dictation step
6. Completion screen with Launch at Login checkbox checked by default

Model download branch behavior:

- User may download selected model.
- User may skip model download.
- Download may continue in background through permission steps.
- If model is ready at test step, run full test.
- If skipped, run mechanical trigger test only.
- If download still in progress, show progress and allow finishing setup now.
- If download fails, offer Retry or Skip for Now.

Completion is always reachable.

Onboarding-completed and app-ready are separate states.

If onboarding was interrupted before completion:

- Show onboarding again next launch.
- Steps check existing status and skip already-completed prerequisites where possible.

## 15. Permissions

Required permissions:

- Microphone
- Accessibility

Microphone:

- Required for AVAudioEngine capture.
- Requested through standard audio permission dialog.

Accessibility:

- Required for synthetic paste/typing events.
- Required for secure-field check.
- Requested with `AXIsProcessTrustedWithOptions`.

Keyboard monitoring:

- Use paired AppKit global and local event monitors for trigger detection.
- Accessibility trust covers global keyboard event delivery and synthetic
  insertion; Textify does not request Input Monitoring separately.
- The local monitor keeps trigger tests functional while Textify is frontmost.

Permission revocation behavior:

- Do not show proactive launch alert.
- Check status when user tries to dictate where possible.
- Microphone/Accessibility revoked:
  - one-time notice per episode
  - menu Permissions status line
  - Settings -> Privacy shows exact status

One-time notice flags:

- `hasShownNoModelNotice`
- `hasShownMicRevokedNotice`
- `hasShownAccessibilityRevokedNotice`
- `hasShownInputMonitoringRevokedNotice` remains decode-compatible legacy
  storage only and is ignored by V1.1 runtime readiness.

Flags reset when their condition resolves.

Flags gate only intrusive notices, not menu status.

## 16. Trigger Model

Default trigger:

- Hold Right Command.

Curated fallback triggers:

- Hold Right Option
- Hold Right Control
- Hold Control + Space

Excluded fallback:

- Fn/Globe, because it is not reliable enough for V1.

No arbitrary custom trigger capture in V1.

Implementation:

- Paired AppKit global/local monitors.
- Observe `flagsChanged`, `keyDown`, and `keyUp` events needed by the configured
  curated trigger.
- Do not consume events.
- Keep monitor callbacks minimal and fast.
- Hop to `DictationController`.

Runtime trigger state:

1. Trigger down starts a 250 ms activation window.
2. Release before 250 ms is an accidental tap and does nothing.
3. Any non-trigger key before activation is treated as normal shortcut use and
   dictation does not start.
4. After 250 ms, recording starts.
5. Recording initially enters an armed/no-speech-yet state.
6. A non-trigger non-modifier key after recording starts but before speech is
   detected is treated as shortcut use: cancel, discard audio, no transcription,
   no insertion.
7. Once speech is detected, extra keys do not cancel recording.
8. Esc always cancels recording before or after speech.
9. Trigger release after speech ends recording and starts transcription/insertion.
10. Trigger release with no speech is a silent no-op.

Reason: this prevents the common accidental case where a user holds Right
Command longer than 250 ms, hesitates, then presses a normal shortcut key.

Trigger Test:

- Uses the same event path as runtime.
- No insertion required.
- Mechanical-only mode possible if no model is installed.
- Passes only after threshold and matching release.
- Extra key before threshold: shortcut/test ignored.
- Extra key after recognized hold: does not fail.
- Esc during recognized hold: cancel detected; not pass.
- Failure states:
  - Tap ignored
  - Shortcut use detected
  - Conflict detected
  - Unsupported on this keyboard

## 17. Dictation State Machine

Central app orchestrator:

- `DictationController`
- `@MainActor`

State enum:

```swift
enum State {
    case idle
    case recording
    case processing
    case inserting
    case error(DictationError)
}
```

Flow:

```text
idle -> recording -> processing -> inserting -> idle
```

Silent no-op paths:

- cancelled while holding
- accidental tap
- full silence
- trigger released with no speech detected
- hallucination-filter discard
- target app changed
- target app terminated
- secure field

Busy behavior:

- Ignore new trigger events when state is not idle.
- Do not queue dictations.

## 18. Overlay

Overlay:

- Small center-bottom recording indicator.
- Compact waveform/level pulse.
- Optional elapsed seconds after a few seconds.
- No transcript preview.
- No success toast.
- No normal completion message.

On trigger release:

- Overlay disappears immediately in the common path.
- If processing exceeds about 400-500 ms, show lightweight delayed processing indicator.
- Show errors only for actionable failures.

Cancel:

- Esc while holding cancels.
- Overlay can show cancelled state briefly.

## 19. Audio Capture

Use AVAudioEngine first.

Canonical provider audio format:

- 16 kHz
- mono
- 16-bit signed linear PCM

Capture:

- Hardware-native input format.
- Convert/downmix through AVAudioConverter.
- Store short dictation audio in memory by default.
- Subprocess spike may materialize a temporary WAV file only when required.
- Delete temporary WAV immediately.

Microphone selection behavior:

- Textify follows macOS System Default microphone by default.
- If selection is System Default, Textify uses the current system default at
  capture start.
- If system default changes while idle, Textify uses the new default next time.
- If an explicitly selected mic disappears, Textify does not silently fall back
  to another mic.
- Missing explicit mic fails with "Selected microphone is unavailable. Choose
  another microphone or System Default."
- If a device change happens during recording, do not switch mid-recording.
- Device change during recording cancels capture, discards audio, and shows
  "Microphone changed. Dictation cancelled."
- If the current stream survives a default-device change during recording, keep
  recording from original stream and apply the new default next time.

Bluetooth/headsets:

- No Bluetooth-specific controls in V1.
- Capture hardware-native format and convert to canonical format.
- If Bluetooth profile changes break capture or conversion, cancel with an
  actionable error.
- Do not show codec/profile warnings in V1.

Audio failure messages:

- Mic permission missing: "Microphone permission is off. Enable it in System
  Settings."
- Selected mic unavailable: "Selected microphone is unavailable. Choose another
  microphone or System Default."
- Capture start failure: "Textify could not start the microphone. Try again or
  choose another microphone."
- Conversion failure: "Textify could not use this microphone format. Choose
  another microphone."
- Device change during recording: "Microphone changed. Dictation cancelled."

Audio failure no-op behavior:

- Capture-start failure: no recording, no transcription, no insertion.
- Conversion failure: discard audio, no transcription, no insertion.
- Device disconnect/change during recording: discard audio, no transcription,
  no insertion.
- Valid capture with no speech: silent no-op.

Real-time speech detection for trigger guard:

- Use the live AVAudioEngine capture stream after conversion to canonical
  16 kHz mono PCM.
- Analyze short RMS windows only.
- Do not use Whisper, tokenization, or a full VAD pass for this guard.
- Frame size: 20 ms.
- Startup grace: ignore first 80 ms after recording starts.
- Track a rolling noise floor from quiet frames.
- A frame is a speech candidate if RMS is above:

```text
max(noiseFloor + 12 dB, -45 dBFS)
```

- Mark `speechDetected = true` only after 120 ms of sustained candidate audio.
- Once true, it stays true until recording ends.
- Isolated spikes do not count.
- Short transients under 120 ms do not count.
- High peak/low-duration bursts, like key clicks, are ignored unless sustained.

This guard only decides whether a later shortcut key should cancel recording.
It does not trim audio and does not decide whether to transcribe. Final edge VAD
and Whisper no-speech metadata still run after release and may silently no-op.

If speech detection is uncertain, keep `speechDetected = false`. This biases the
guard toward protecting normal shortcut use.

Silence/VAD:

- Conservative edge-only trimming.
- No mid-speech trimming.
- 200-300 ms post-release capture grace to avoid clipped speech.
- Leave about 150 ms safety pad at detected edges.
- When uncertain, do not trim.
- Full-clip no speech skips transcription and silently no-ops.

No raw audio retention by default.

## 20. Transcription Runtime

Local on-device transcription only for V1.

First runtime:

- whisper.cpp

Implementation stages:

1. Mock provider
2. Debug-only subprocess spike
3. Native whisper.cpp wrapper before V1 release

SubprocessProvider:

- Debug/spike-only.
- Not shipped in release.
- Does not support Custom Words.
- Uses git-ignored `.spike/` local setup.

Native runtime:

- `WhisperRuntime`
- Actor in `TextifyTranscription`
- Owns loaded native whisper context.
- Owns model load/unload/switch.
- Owns in-flight safety.
- Uses serial `DispatchQueue` plus continuation for blocking inference.
- Does not run `whisper_full()` on Swift cooperative concurrency pool.

Runtime lifecycle:

- On launch, reconcile installed models, then preload the active valid model in
  the background.
- Only one `whisper_context` exists at a time.
- Active model stays loaded while Textify is running unless user switches model,
  active model is deleted, validation fails, app quits, or macOS reports serious
  memory pressure while Textify is idle.
- Keep the active model loaded for responsiveness.
- Allow defensive unload on memory pressure.

Warmup:

- After a successful load, run one low-priority warmup using a short silent
  16 kHz mono buffer.
- Ignore the warmup transcript.
- Do not use custom vocabulary or initial prompt during warmup.
- Mark model Ready only after load and warmup complete.
- If warmup fails, treat the model as failed to load.

Memory pressure:

- If idle: unload the model, keep active model id, and mark status
  "Unloaded to save memory".
- If recording: cancel recording, discard audio, unload, and show
  "Dictation cancelled because macOS reported low memory."
- If transcribing: do not forcibly cancel V1 transcription; finish if possible,
  then unload if pressure remains.
- Next dictation attempt reloads the active model first.

Sleep/wake:

- On sleep while recording: cancel and discard audio.
- On sleep while idle: keep state; no special UI.
- On wake: if a model is loaded, run a lightweight health/warmup check in the
  background.
- If wake health check fails, unload and reload the active model.

Trigger while model is loading:

- Do not start recording.
- Show "Preparing model. Try again in a moment."
- If loading finishes while the user is still holding the trigger, do not
  auto-start recording.
- User must release and hold again.

Provider protocol remains narrow:

```swift
protocol TranscriptionProvider {
    func transcribe(_ audio: CanonicalAudioBuffer) throws -> TranscriptionResult
}
```

Result includes:

- text
- no speech probability
- average log probability
- compression ratio
- processing metadata needed by diagnostics/filtering

No streaming partials in V1.

No transcription cancel after release in V1.

## 21. Model System

No bundled model files.

Onboarding downloads a curated model or lets user skip.

Current catalog support tiers:

- Fast
- Recommended
- Balanced
- Accurate
- Specialist
- Experimental

UI shows both friendly tier and actual model name.

Initial V1 curated model list:

| Tier | UI model name | whisper.cpp family | File | Default |
| --- | --- | --- | --- | --- |
| Fast | Fast - Whisper base.en | `base.en` | `ggml-base.en-q5_1.bin` | No |
| Balanced | Balanced - Whisper small.en | `small.en` | `ggml-small.en-q5_1.bin` | Yes |
| Accurate | Accurate - Whisper medium.en | `medium.en` | `ggml-medium.en-q5_0.bin` | No |

The default onboarding recommendation is Balanced - Whisper small.en.

Do not use `tiny.en` as the V1 Fast tier. Its download size is attractive, but
its quality is too likely to harm first-run dictation trust.

Tiers are curated presets:

- model file(s)
- decoding parameters
- optional hallucination thresholds

Users may import verified Whisper-compatible GGML/GGUF files into managed
storage. Arbitrary runtime plugins and non-Whisper file formats remain
unsupported.

Multiple installed models are allowed.

Only one model is loaded at a time.

Model switching:

- immediate
- no app restart
- not during active recording/transcription
- the active engine runtime serializes/awaits in-flight work
- switch controls are disabled during recording/transcription with "Finish
  current dictation to switch models."
- on switch, unload old model, load and warm up new model, then persist it as
  active
- if new model load fails, try to reload previous active model and show
  "Could not load Accurate - Whisper medium.en. Still using Balanced - Whisper
  small.en."

Model load states shown in Settings -> Models:

- Loading
- Preparing
- Ready
- Unloaded to save memory
- Failed to load

Menu/overlay may show "Preparing Balanced - Whisper small.en..." when relevant.

No percentage for model loading in V1; use spinner/state text only.

Model load errors:

- Missing file: "Model file is missing. Delete and download it again."
- Checksum failure: "Model verification failed. Redownload this model."
- Load failure: "Textify could not load this model. Try another model."
- Memory failure: "Not enough memory to load this model. Choose a smaller model
  or close other apps."

Model deletion:

- allowed
- confirmation required
- active model deletion unloads runtime and leaves app with no active model

Model storage:

```text
~/Library/Application Support/Textify/
├── vocabulary.json
├── custom-words.json
├── excluded-apps.json
├── Models/
│   ├── installed.json
│   ├── .downloading/
│   ├── <model-id>/
│   │   └── <model-file>
├── ManifestCache/
│   ├── manifest.json
│   └── manifest.json.sig
└── Diagnostics/
    └── log-YYYY-MM-DD.jsonl
```

Downloads:

- one at a time
- check disk space before starting
- stage in `.downloading/`
- verify SHA-256 before install
- atomically move into final model directory
- clean partial downloads on failure/cancel/launch cleanup
- best-effort resume
- quitting during download asks confirmation

Minimum free-space rule before starting a model download:

```text
modelSizeBytes + max(500 MB, 20% of modelSizeBytes)
```

Check available space on the volume that contains Textify Application Support.
Because staging and final install live on the same volume, do not require 2x
model size.

Download progress UI shows:

- tier and actual model name
- filename
- total size
- downloaded / total
- percent
- current speed
- ETA
- phase
- Cancel action
- Retry action when applicable

Download phases:

- Checking space
- Downloading
- Interrupted
- Verifying
- Installing
- Installed
- Failed
- Cancelled

Retry/cancel behavior:

- Only one active download in V1.
- No download queue.
- Transient network failures auto-retry up to 3 times with short backoff.
- After automatic retries fail, show Retry.
- Retry resumes if safe, otherwise restarts.
- Cancel stops the download and deletes the partial file.
- Checksum, signature, or manifest mismatch failures delete the partial and
  require a clean retry.

Resume behavior:

- Store partial bytes in `.downloading/`.
- Store sidecar metadata: model id, expected size, SHA-256, URL,
  ETag/Last-Modified if available, and bytes downloaded.
- Resume with HTTP Range only if URL, expected size, and server validators still
  match.
- If resume cannot be trusted, restart from byte 0.
- On launch, resume only valid interrupted downloads.
- Delete stale or invalid partials on launch cleanup.

Download failure messages:

- Disk: "Not enough disk space to download Balanced - Whisper small.en. Free at
  least 1.1 GB and try again."
- Network: "Download interrupted. Check your connection and retry."
- Resume restart: "Textify could not safely resume this download, so it will
  restart."
- Verification: "The downloaded model could not be verified. Textify deleted
  it."
- Manifest removed: "This model is no longer available in the current model
  list."
- Cancel: "Download cancelled."

Background behavior:

- Downloads continue after onboarding if the app remains running.
- User can close onboarding and monitor/cancel/retry from Settings -> Models.
- If the user quits during a download, ask for confirmation.
- Confirmed quit stops the transfer but keeps a valid resumable partial when
  possible.

Dictation while downloading:

- Textify can dictate with an already-installed active model while another
  model downloads.
- Downloading, verifying, and installing do not unload or switch the active
  model.
- If no active model exists, the first successfully installed model
  auto-activates.
- If an active model already exists, newly downloaded models do not auto-switch.

Backup policy:

- Include user settings, vocabulary, custom words, excluded apps, installed metadata.
- Exclude model binaries.
- Exclude download temp files.
- Exclude manifest cache.
- Exclude diagnostics.

On launch:

- Read `installed.json`.
- Verify each installed model file exists and checksum matches.
- Drop invalid entries.
- Do not auto-promote another installed model if active model is invalid.
- Self-heal `installed.json`.
- Preload active valid model in background.
- Do not wait on network manifest refresh to use an already-installed model.

## 22. Model Manifest

Built-in manifest:

- Bundled in app resources.
- Lists curated model options.
- No model binaries bundled.

Remote manifest:

- HTTPS only.
- Strict JSON schema validation.
- Signed with EdDSA.
- Public verification key embedded in app.
- Invalid or unsigned manifest is rejected.
- No degraded trust mode.

Remote manifest hosting:

- `manifest.json` and `manifest.json.sig` live on GitHub Pages.
- Model file URLs inside the manifest point either to immutable Textify GitHub
  Release assets or exact Hugging Face
  `resolve/<40-character-lowercase-commit>/<path>` files.
- Reject mutable refs, credentials, ports, queries, fragments, percent-encoded
  or traversing paths, and every unapproved host or URL shape.
- The manifest includes upstream source/provenance/license metadata for each
  model.
- New model bytes require a new immutable URL or commit, new size/checksum, and
  newly signed manifest.

Fallback precedence:

1. Verify the complete bundled manifest/signature pair and the fetched remote
   manifest/signature pair independently.
2. If both are valid, select the one with the newer signed `generatedAt`
   timestamp; an equal timestamp may select remote.
3. If remote fetch or verification fails, use the valid bundled manifest.
4. An incomplete or invalid bundled pair is a release-integrity failure.

Select one manifest source wholesale. Do not merge sources.

Already installed models keep working even if removed from current manifest.

Deprecated installed model UI:

- show cached metadata
- badge: "No longer in curated list"
- allow Set Active if installed and valid
- allow Delete
- no re-download button
- no proactive notification

Manifest schema shape:

The example below uses placeholder size and checksum values. Release manifests
must contain real byte sizes and SHA-256 values.

```json
{
  "manifestVersion": 1,
  "generatedAt": "2026-07-01T00:00:00Z",
  "models": [
    {
      "id": "whisper-base-en-fast",
      "displayName": "Fast - Whisper base.en",
      "tier": "fast",
      "description": "Fast local English dictation with better first-run quality than tiny.en.",
      "sizeBytes": 0,
      "files": [
        {
          "filename": "ggml-base.en-q5_1.bin",
          "url": "https://github.com/Player0109/Textify/releases/download/models-v1/ggml-base.en-q5_1.bin",
          "sha256": "lowercase-hex-sha256",
          "sizeBytes": 0
        }
      ],
      "licenses": [
        {
          "scope": "converted ggml model file",
          "spdxId": "MIT",
          "name": "MIT License",
          "licenseTextUrl": "https://github.com/Player0109/Textify/releases/download/models-v1/ggml-base.en-q5_1.LICENSES.txt"
        }
      ],
      "provenance": {
        "sourceName": "ggerganov/whisper.cpp",
        "sourceUrl": "https://huggingface.co/ggerganov/whisper.cpp",
        "sourceRevision": "<pinned upstream revision>",
        "sourceFile": "ggml-base.en-q5_1.bin",
        "originalModelName": "OpenAI Whisper base.en",
        "originalModelUrl": "https://huggingface.co/openai/whisper-base.en",
        "mirroredBy": "Textify",
        "mirroredAt": "YYYY-MM-DD"
      },
      "runtimeParameters": {
        "language": "en",
        "detectLanguage": false,
        "translate": false,
        "strategy": "greedy",
        "beamSize": 1,
        "bestOf": 1,
        "temperature": 0.0,
        "temperatureFallback": [],
        "noContext": true,
        "tokenTimestamps": false,
        "maxAudioSeconds": 60
      },
      "hallucinationThresholds": {
        "noSpeechProbabilityMax": 0.60,
        "avgLogProbabilityMin": -1.00,
        "compressionRatioMax": 2.40
      },
      "minAppVersion": "1.0.0"
    }
  ]
}
```

Do not store thread count or Metal settings in manifest.

Use `licenses: []`, not a single `license`, because the converted file source,
original model, and runtime dependency may have different notices.

Model source/license UI:

- Onboarding and Settings -> Models show a small Source & License link for each
  model.
- Model detail view shows upstream source, original model, license SPDX IDs,
  selected source filename/path, and SHA-256.
- Do not show legal walls or download-blocking license modals in V1.

Model license text storage:

- Store V1 curated model license/notices in app resources so they are visible
  before download and offline.
- For Textify-hosted mirrors, publish the same license/provenance files as
  GitHub Release assets next to each model binary. For commit-pinned upstream
  files, keep the applicable notices in the app and exact provenance in the
  signed catalog.
- Installed model metadata caches the manifest's license/provenance fields.

Runtime parameter policy for all initial V1 models:

This block documents the initial English Whisper presets. The current
multi-model catalog may declare a fixed supported language or language
detection according to an engine's verified capabilities. Capture uses each
entry's `maxAudioSeconds`; production policy accepts 1–60 seconds generally and
at most 29 seconds for Paraformer so its 30-second native input window cannot
silently truncate post-release audio.

```json
{
  "language": "en",
  "detectLanguage": false,
  "translate": false,
  "strategy": "greedy",
  "beamSize": 1,
  "bestOf": 1,
  "temperature": 0.0,
  "temperatureFallback": [],
  "noContext": true,
  "tokenTimestamps": false,
  "maxAudioSeconds": 60
}
```

Specific runtime decisions:

- Force English with `language: "en"`.
- Do not auto-detect language.
- Do not translate.
- Use deterministic greedy decoding.
- No beam search in V1.
- Use `temperature: 0.0`.
- Disable temperature fallback in V1.
- Disable token timestamps.
- Manifest declares `maxAudioSeconds: 60`, but capture/runtime enforce it before
  calling whisper.cpp.
- Thread count is runtime-owned, not manifest-owned.
- Metal/GPU enablement and fallback are runtime-owned, not manifest-owned.

Initial hallucination thresholds are the same for all three V1 tiers:

```json
{
  "noSpeechProbabilityMax": 0.60,
  "avgLogProbabilityMin": -1.00,
  "compressionRatioMax": 2.40
}
```

Per-tier threshold overrides remain allowed later, but require QA evidence.

### 22.1 Model Curation Checklist

Before adding or updating a curated model:

- Confirm there is a model suggestion issue or maintainer decision.
- Verify the upstream artifact has a clear redistribution license.
- Record exact upstream URL, revision/commit, filename, size, and audit date.
- Download from upstream directly; never accept user-uploaded binaries.
- Compute SHA-256 locally.
- Run the engine-specific native smoke test and prove the declared accelerator.
- Add/update license text and notices.
- Use either an immutable Textify GitHub Release asset or an exact commit-pinned
  Hugging Face file. If Textify mirrors the bytes, publish the applicable
  license and provenance sidecars with the release asset.
- Update built-in/remote manifest with URL, size, SHA-256, licenses,
  provenance, runtime preset, and min app version.
- Sign the manifest and verify a clean install download path.

If license provenance is unclear, the model is not eligible for V1 curation.

### 22.2 Model Manifest Signature

Use a detached JSON signature envelope at `manifest.json.sig`.

Do not use raw `.sig` bytes, inline signatures, JWS, or JSON canonicalization in
V1.

Signature file format:

```json
{
  "signatureVersion": 1,
  "signatureType": "io.github.Player0109.Textify.model-manifest",
  "algorithm": "Ed25519",
  "keyId": "model-manifest-v1",
  "manifestFile": "manifest.json",
  "contentType": "application/vnd.textify.model-manifest+json;version=1",
  "contentSHA256": "lowercase-hex-sha256-of-exact-manifest-json-bytes",
  "signature": "base64url-no-padding-ed25519-signature"
}
```

Canonical bytes to sign are not the parsed JSON. Sign this exact UTF-8 payload,
with LF newlines and a final LF:

```text
TEXTIFY-MODEL-MANIFEST-SIGNATURE-V1
signatureVersion=1
signatureType=io.github.Player0109.Textify.model-manifest
algorithm=Ed25519
keyId=model-manifest-v1
manifestFile=manifest.json
contentType=application/vnd.textify.model-manifest+json;version=1
contentSHA256=<lowercase-hex-sha256-of-exact-manifest-json-bytes>
```

Verification order:

1. Download `manifest.json` and `manifest.json.sig` over HTTPS.
2. Parse `.sig` with a strict schema; reject unknown or missing fields.
3. Require `signatureVersion == 1`.
4. Require `algorithm == "Ed25519"` exactly.
5. Require known embedded `keyId`; never fetch keys remotely.
6. Compute SHA-256 over the exact downloaded `manifest.json` bytes.
7. Compare to `contentSHA256`.
8. Rebuild the canonical payload exactly.
9. Verify the Ed25519 signature using the embedded public key for `keyId`.
10. Only then parse and strict-schema-validate `manifest.json`.

`keyId` is an opaque ASCII identifier into the app's embedded manifest
verification key table. Unknown `keyId` means reject, with no degraded trust
path.

## 23. Post-Processing Pipeline

Pipeline order:

1. Raw ASR output
2. Punctuation/newline/symbol command normalization
3. Adjacent punctuation dedup/collapse
4. Light filler cleanup
5. Vocabulary replacement
6. Final whitespace/capitalization pass
7. Plain text output for insertion

No cleanup intensity setting.

No LLM cleanup in V1.

No prompt profiles in V1.

No per-app cleanup behavior in V1.

### 23.1 Reserved Spoken Command Table

All commands are case-insensitive phrase matches.

Document canonical command plus aliases in `docs/SPEC.md`. Synonyms are aliases,
not separate commands.

| Canonical | Aliases | Output | Spacing |
| --- | --- | --- | --- |
| comma | | `,` | attach before, one space after unless followed by punctuation/newline/end |
| period | full stop | `.` | attach before, one space after unless followed by punctuation/newline/end |
| exclamation mark | exclamation point | `!` | attach before, one space after unless followed by punctuation/newline/end |
| question mark | | `?` | attach before, one space after unless followed by punctuation/newline/end |
| colon | | `:` | attach before, one space after unless followed by punctuation/newline/end |
| semicolon | | `;` | attach before, one space after unless followed by punctuation/newline/end |
| open quote | | `"` | one space before unless start of text/line, no space after |
| close quote | | `"` | no space before, one space after unless followed by punctuation |
| new line | | `\n` | strip surrounding whitespace |
| new paragraph | | `\n\n` | strip surrounding whitespace |
| hyphen | | `-` | strip surrounding whitespace |
| open parenthesis | open paren | `(` | one space before unless start, no space after |
| close parenthesis | close paren | `)` | no space before, one space after unless followed by punctuation |
| at sign | | `@` | strip surrounding whitespace |
| ampersand | | `&` | one space before and after |
| forward slash | | `/` | strip surrounding whitespace |
| backslash | | `\` | strip surrounding whitespace |

Excluded commands:

- dash
- hashtag

Straight ASCII quotes only.

Use both whisper automatic punctuation and explicit command words. Dedup adjacent
punctuation after command substitution. Prefer command-inserted punctuation when
there is a collision.

### 23.2 Capitalization

Final capitalization is minimal and additive only:

- Capitalize first letter of transcript.
- Capitalize first letter after sentence-ending punctuation.
- Capitalize standalone `I`.
- Never lowercase model output.
- Never alter protected replacement spans.
- Do not infer proper nouns.
- Do not infer acronyms.

### 23.3 Filler Cleanup

Light cleanup always on.

Remove obvious standalone fillers:

- um
- uh
- you know
- like, when clearly filler

Do not aggressively rewrite content.

### 23.4 Hallucination Safeguards

Use whisper.cpp metadata:

- no speech probability
- average log probability
- compression ratio

Also use a small known-hallucination denylist for common Whisper boilerplate.

Safeguards are hardcoded, not user-configurable.

Per-model manifest threshold overrides are allowed.

Flagged output silently no-ops and logs technical metadata.

## 24. Insertion

User-facing behavior:

- Text appears automatically at the current cursor after release.

Implementation:

- Paste-first.
- Simulated typing fallback only on mechanical API failure.
- No per-app insertion profiles in V1.

Insertion failure definitions:

- Mechanical paste failure means Textify could not prepare or send the paste
  operation.
- Unobservable paste outcome means Textify sent the paste keystroke but cannot
  prove whether the target accepted it.

If the complete Command-V event sequence was posted, Textify must not attempt
simulated typing fallback.

Insertion target:

- Capture frontmost app at key-down.
- Store app/pid/bundle identity for current session.
- Check excluded apps at key-down.
- Revalidate same frontmost app before insertion.
- If target app changed or terminated, abort silently.
- Do not force refocus.
- Do not redirect to a new app.
- Do not track focused Accessibility element identity over time.

Excluded app runtime behavior:

- If captured bundle ID is in the user exclusion list, do not record, do not
  transcribe, and do not insert.
- Show a small temporary overlay while held: "Textify disabled for this app."
- Overlay disappears immediately on release.
- Secure/password field abort remains silent and separate.

Secure field check:

- Immediately before insertion, perform a fresh focused-element AX role/subrole check.
- If secure/password field is positively detected, abort silently.
- If check fails or is indeterminate, fail open and proceed.

Clipboard sequence:

1. Snapshot all pasteboard items and all raw type data.
2. Record pasteboard `changeCount`.
3. Clear pasteboard and write final dictated text as plain string.
4. Mark transient/concealed pasteboard types best-effort.
5. Post synthetic Command-V.
6. Wait about 150-250 ms.
7. Restore previous clipboard only if `changeCount` still matches Textify's write.
8. If pasteboard changed in the meantime, skip restore.

No user-facing error for clipboard restoration issues in V1.

Simulated typing fallback is allowed only when all are true:

- Target app still matches the key-down app.
- Fresh secure-field check passes.
- Text is non-empty.
- Clipboard could not be safely used before paste was attempted, or the paste
  event sequence could not be created before any paste event was posted.
- No complete Command-V event sequence was posted.
- Text length is <= 500 Unicode scalars.
- Text contains no newlines, tabs, or control characters.
- Input event posting is still available.
- Frontmost app remains unchanged before fallback starts.

Simulated typing fallback is not allowed when:

- Command-V was posted but insertion cannot be confirmed.
- Paste might be delayed.
- Target app blocks paste.
- Clipboard restore fails.
- AX readback is unavailable.
- Focused element cannot be inspected.
- Text is over 500 characters.
- Text contains newlines.

Fallback typing behavior:

- Use Unicode text events, not keyboard-layout-dependent key mapping.
- Chunk into at most 20 Unicode scalars per event.
- Wait about 8-12 ms between chunks.
- Revalidate frontmost app before each chunk.
- Stop immediately if target changes.
- No undo attempt for partial fallback typing.

Fallback failure/no-op behavior:

- If paste was sent, restore clipboard best-effort, then stop. No fallback.
- If paste could not be attempted and fallback is ineligible, perform no
  insertion.
- Show only: "Textify could not insert text here."
- Do not show clipboard-specific user errors.
- Clipboard restore failures are diagnostics-only.

Insertion diagnostics may include:

```json
{
  "event": "insertion_attempt",
  "textLengthBucket": "201-500",
  "pasteboardSnapshotSucceeded": true,
  "pasteboardWriteSucceeded": true,
  "pasteEventPosted": true,
  "pasteOutcomeObservable": false,
  "fallbackAttempted": false,
  "fallbackBlockedReason": "paste_outcome_unobservable",
  "fallbackChunks": 0,
  "targetChanged": false,
  "secureFieldDetected": false,
  "clipboardRestoreSucceeded": true,
  "durationMs": 123
}
```

Diagnostics must never include inserted text or clipboard contents.

Plain text only.

No automatic leading/trailing space around inserted text.

Normal target app undo handles unwanted insertion.

No dedicated Textify undo in V1.

## 25. Privacy And Data Retention

No user-facing transcript history.

No internal transcript history by default.

Diagnostics do not contain dictated text.

Audio:

- In memory only.
- Not stored by default.
- Debug raw audio retention is not part of V1.

Clipboard:

- Clipboard contents are snapshot/restored for insertion only.
- Clipboard contents are never logged.
- Clipboard contents are never stored in history.

Settings stored locally:

- app preferences
- selected model
- vocabulary replacements
- custom words
- excluded apps
- onboarding state
- one-time notice flags

No custom encryption at rest in V1.

## 26. Diagnostics

Diagnostics:

- JSONL logs.
- One file per day.
- 14-day retention.
- Not user-configurable.
- Clear Diagnostics Log button.
- Excluded from backups.

Closed event schema only.

No generic `message`, `details`, `content`, `text`, `transcript`, or similar
free-text fields.

Forbidden in diagnostics:

- dictated text
- transcript text
- audio data
- clipboard contents
- target app bundle IDs
- vocabulary contents
- custom words contents
- excluded apps list contents
- raw free-form error messages from libraries

Allowed as counts/enums/metrics:

- app version
- macOS version
- machine model/chip class
- active model ID/tier
- installed model IDs/tiers
- manifest source
- vocabulary entry count
- custom words count
- excluded apps count
- durations
- error codes
- no speech probability
- average log probability
- compression ratio
- insertion method enum
- pipeline stage timings
- event enum such as `dictation_blocked_excluded_app`

For excluded-app blocking, diagnostics must not log app name, bundle ID, window
title, or focused element.

Export Diagnostics:

- Single human-readable JSON file.
- Not a ZIP in V1.
- User-initiated only.
- Safe to attach to GitHub issue.
- Contains no dictated text.
- Contains no target app IDs.

Developer Mode verbose diagnostics:

- Still no content fields.
- More numeric/runtime detail only.

## 27. Architecture

Initial SwiftPM targets:

- `WhisperCppVendor`
- `TextifyWhisperShim`
- `TextifyCore`
- `TextifyAudio`
- `TextifyTranscription`
- `TextifyModels`
- `TextifyInsertion`
- `TextifyHotkeys`
- `TextifyDiagnostics`
- `TextifySettings`
- `Textify` executable

Deferred until native wrapper stage:

- `CWhisper` vendored C target
- Native whisper.cpp integration may use `WhisperCppVendor` and
  `TextifyWhisperShim` names instead of `CWhisper`; the important boundary is a
  vendored native target plus a thin Textify-owned shim.

Vendoring whisper.cpp:

- Directly vendor minimal source subset.
- No submodule.
- No build-time network fetch.
- No CMake dependency in the app build.
- Preserve upstream license.
- Record upstream commit/tag and included subset.
- Vendor only files needed for Textify's Apple-Silicon Metal path.
- Pin by full upstream commit SHA, never `master` or `main`.
- Prefer zero local patches. Document unavoidable patches in `UPSTREAM.md`.

Vendor layout:

```text
Vendor/
  whisper.cpp/
    UPSTREAM.md
    LICENSE
    README.TEXTIFY.md
    upstream/
      include/
      src/
      ggml/
Sources/
  TextifyWhisperShim/
    TextifyWhisperShim.h
    TextifyWhisperShim.mm
  TextifyTranscription/
    WhisperRuntime.swift
```

`Vendor/whisper.cpp/UPSTREAM.md` records:

- upstream repo URL
- full commit SHA
- tag, if any
- date copied
- included paths
- excluded paths
- local patches

SwiftPM target shape:

- `WhisperCppVendor`: C/C++/ObjC++ static library target for vendored
  whisper.cpp/ggml sources.
- `TextifyWhisperShim`: thin C/ObjC++ shim exposing only Textify's stable
  C-compatible surface.
- `TextifyTranscription`: Swift wrapper/runtime actor that owns model loading,
  transcription, threading, and lifecycle.

Build flag ownership:

- `Package.swift` owns C/C++/Metal compile and linker settings.
- The thin Xcode project consumes the SwiftPM package.
- Do not duplicate vendored file membership in Xcode.
- Xcode project does not own whisper.cpp build flags.
- Remote model manifest never controls compile flags, thread count, Metal, or
  GPU behavior.
- Release builds target macOS 14+ arm64 only.
- Enable the Metal path for Apple Silicon builds.
- Link required Apple frameworks from SwiftPM, such as `Accelerate`, `Metal`,
  and `Foundation`, as needed by the chosen upstream subset.

Core ML:

- Do not bundle Core ML model artifacts in the app.
- Install only exact signed catalog artifacts into managed model storage.
- Do not enable `WHISPER_COREML` build paths.
- Whisper uses the Metal path. Released FluidAudio batch engines may use Core
  ML only when Textify proves Neural Engine-preferred operations and fails
  closed instead of silently accepting CPU fallback.

Exclude from the V1 vendor snapshot:

- CLI examples
- server examples
- bench tools
- sample audio
- model download scripts
- bindings for other languages
- tests not needed for Textify's build
- CMake build output

whisper.cpp update checklist:

- Open a maintainer issue for the bump.
- Choose upstream commit SHA and record reason.
- Recreate vendor snapshot from clean upstream.
- Confirm no network fetch remains in SwiftPM/Xcode build.
- Review license changes and new dependencies.
- Reapply/document any local patches.
- Build SwiftPM Release arm64 clean.
- Build the thin Xcode app clean.
- Run smoke tests with Fast/Balanced/Accurate models.
- Verify Metal path works on Apple Silicon.
- Verify CPU fallback behavior if supported.
- Verify no CLI/server/download tools are shipped.
- Update `UPSTREAM.md`, `THIRD_PARTY_NOTICES.md`, and app acknowledgments.

Dependency policy:

- First-party native frameworks for hotkeys, menu bar, settings, downloads.
- No SQLite in V1.
- Use JSON/UserDefaults/JSONL.
- Sparkle is an accepted third-party exception because Apple has no equivalent
  direct-distributed update system.
- whisper.cpp is the accepted native ASR dependency.

Concurrency:

- `DictationController`: `@MainActor`
- AppKit keyboard-monitor callback: minimal, hop to MainActor
- Audio capture: actor plus real-time callback discipline
- Whisper inference: actor state plus serial GCD queue for blocking C call
- Diagnostics logger: actor
- TextifyCore: synchronous pure functions
- Insertion: MainActor/AppKit boundary

Whisper pointer safety:

- Wrap native context pointer in minimal `@unchecked Sendable` box.
- Extract pointer inside actor isolation.
- Dispatch blocking inference without reading actor state in closure.
- Track in-flight task.
- Await in-flight task before unload/switch.

## 28. Manual QA

Release-blocking smoke test:

1. Fresh onboarding on clean machine/account.
2. Core dictation loop in TextEdit/Notes, browser field, terminal/code editor.
3. Clipboard restoration.
4. Secure field protection.
5. Excluded apps.
6. Clean DMG install and Gatekeeper behavior.
7. Sparkle update success and tampered update rejection.
8. Model download and SHA-256 verification.
9. Diagnostics export contains no dictated text.
10. Launch at Login, including `.requiresApproval` if triggered.

Periodic regression checks:

- each fallback trigger
- overlay timing threshold
- Keep Textify in the Dock migration, opt-out, and relaunch behavior
- main-window close, Dock reopen, and menu-bar Open Textify behavior
- Reset Onboarding
- Reset All Settings
- Vocabulary and Custom Words
- deprecated model reconciliation
- simulated typing fallback

## 29. Automated Tests

Day-one automated tests:

- TextifyCore pipeline
- command table
- spacing/dedup
- filler cleanup
- vocabulary replacement boundaries
- protected replacement spans
- capitalization
- hallucination filters
- TextifyModels manifest parsing
- manifest signature verification
- SHA-256 verification
- installed model reconciliation
- manifest precedence
- TextifyAudio pure VAD/resampling fixtures
- TextifyDiagnostics schema and no-content invariants
- TextifySettings persistence round-trips
- DictationController state machine with fakes
- WhisperRuntime concurrency with fake backend

Manual-only:

- real AppKit global/local keyboard-monitor behavior
- real TCC permissions
- real cross-app insertion
- secure field behavior
- real Metal/whisper accuracy
- Sparkle update installation
- notarization/Gatekeeper
- UI snapshot testing

## 30. Out Of Scope For V1

These are not V1 commitments:

- Intel Mac support
- Mac App Store distribution
- sandboxing
- cloud transcription
- Apple Speech fallback
- arbitrary runtime plugins and unverified non-Whisper model formats
- arbitrary hotkey capture
- Fn/Globe trigger
- toggle recording mode
- streaming partial transcription
- long-form transcription workspace
- file transcription
- per-app profiles
- per-app vocabulary
- cleanup intensity settings
- spoken punctuation toggle
- filler cleanup toggle
- prompt profiles
- LLM rewriting
- local LLM cleanup
- user-facing transcript history
- searchable history
- dedicated undo-last-insertion shortcut
- custom model storage path
- proxy settings UI
- crash reporting
- product analytics
- automatic model binary downloads
- model rollback UI
- full localization
- UI snapshot testing infrastructure
- public roadmap

## 31. Implementation Start Plan

The V1 product decisions are sufficient to start implementation.

No product decision blocks coding.

Start with a mock-first vertical path. Do not start with whisper.cpp, Sparkle,
notarization, or real global keyboard monitoring.

### 31.1 Milestone Sequence

1. Repo Scaffold
   - Create `Package.swift`, target folders, test targets,
     `script/build_and_run.sh`, `README.md`, `LICENSE`,
     `ACKNOWLEDGMENTS.md`, and `THIRD_PARTY_NOTICES.md`.
   - Scaffold targets from spec: `TextifyCore`, `TextifyAudio`,
     `TextifyTranscription`, `TextifyModels`, `TextifyInsertion`,
     `TextifyHotkeys`, `TextifyDiagnostics`, `TextifySettings`, and `Textify`.
   - Proof: `swift build` and `swift test` pass with empty smoke tests.

2. Pure Text Pipeline
   - Build command normalization, punctuation spacing, filler cleanup,
     vocabulary replacements, capitalization, and hallucination filters.
   - Proof: automated tests for command table, protected replacement spans, no
     lowercase rewrites, and silent no-op filters.

3. Diagnostics And Persistence
   - Build JSON/UserDefaults/JSONL persistence, diagnostics schema, retention,
     and export redaction rules.
   - Proof: tests prove dictated text, target app IDs, vocabulary contents, and
     clipboard contents cannot enter diagnostics.

4. Model Manifest System
   - Build manifest parsing, strict schema, detached signature verification,
     SHA-256 verification, and installed model reconciliation.
   - Mock downloads with local fixture files first.
   - Proof: valid signed fixture passes; tampered manifest/model fails.

5. Dictation State Machine With Fakes
   - Build `DictationController` using fake trigger, fake audio, fake
     transcription, and fake insertion.
   - Include Q348/Q349 armed/no-speech shortcut guard.
   - Proof: tests for tap ignored, shortcut cancel, speech detected, Esc cancel,
     and release transcribes.

6. Audio Capture Boundary
   - Add `AVAudioEngine` capture behind protocol.
   - Build microphone selection model, input level meter, lightweight speech
     detector, and edge VAD fixtures.
   - Proof: unit tests for detector/VAD; manual proof that mic meter works.

7. Insertion
   - Build paste-first insertion, clipboard restore, and conservative simulated
     typing fallback.
   - Proof: fake pasteboard/event tests; manual TextEdit/Notes secure-field
     smoke test later.

8. Minimal App UI
   - Build LSUIElement menu bar app, onboarding, Settings tabs, overlay, and
     runtime status.
   - Use mock transcription provider.
   - Proof: local `.app` launches, onboarding completes, settings persist, and
     mock dictation inserts.

9. Hotkeys And Keyboard Monitoring
   - Implement curated triggers, Trigger Test, Accessibility status, paired
     AppKit global/local monitoring, and fallback trigger behavior.
   - Proof: state tests with fakes plus manual full-app TCC test.

10. Model Downloads
    - Implement GitHub-hosted manifest fetch, one-at-a-time downloads, staging,
      resume, cancel, verify, and install.
    - Proof: local test server or fixture download; checksum mismatch deletes
      partial; active model remains usable during another download.

11. Native whisper.cpp Runtime
    - Vendor pinned minimal whisper.cpp subset, add shim, and implement
      `WhisperRuntime`.
    - Proof: load/warmup/switch/unload tests with fake backend first, then real
      local smoke with one curated model.

12. Thin Xcode And Distribution
    - Add Xcode project for app bundle, entitlements, Sparkle embedding,
      signing, notarization, and DMG.
    - Proof: `xcodebuild` archive, ad-hoc local run, then signed/notarized
      release candidate.

### 31.2 Safely Deferred Until Milestone

- Exact whisper.cpp upstream commit: defer until Milestone 11.
- Final model SHA-256 values and release URLs: defer until Milestone 10.
- Sparkle private key material and notarization credentials: defer until
  Milestone 12.
- Threshold tuning beyond current defaults: defer until audio/runtime QA.
- App icon/final visual polish: defer until UI milestone.
