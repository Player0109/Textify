# Electron migration

The owner approved macOS, Windows, and Linux together, with explicit Copy and
manual paste wherever safe automatic insertion is unavailable on Wayland.
The native Swift app remains usable throughout migration.

## First milestone

1. Shared Electron/React interface and TypeScript dictation controller.
   Verify cancellation, short taps, stale callbacks, silence, and one insertion.
2. Microphone capture in a dedicated sandboxed renderer; native whisper.cpp in
   a separate local worker. Verify real 16 kHz PCM transcription without writing
   audio or dictated text to disk.
3. Native macOS/Windows insertion with captured-target revalidation and clipboard
   restoration. Linux exposes explicit Copy until an insertion path has the
   same safeguards. X11 uses native key observation; Wayland uses the desktop
   GlobalShortcuts portal, including activation and deactivation signals.
4. Build, test, and package on each OS. Local macOS checks do not establish
   Windows/Linux desktop behavior; those remain explicit release gates.

## Structure

- `electron/src/core`: dictation lifecycle, audio rules, text processing.
- `electron/src/main`: Electron lifecycle, verified model storage, native
  process supervision, permissions, platform integration, narrow IPC handlers.
- `electron/src/renderer`: settings/onboarding and isolated audio capture.
- `electron/native`: local inference worker and native insertion helpers.
- `electron/tests`: behavior, integrity, IPC and lifecycle tests.

Use a separate application identity and data directory (`Textify Electron`)
during development. Importing a known model copies and verifies its bytes;
never change the Swift app's installed files or preferences.

## Product and design

Keep the product a quiet dictation utility: a persistent settings window,
tray/menu-bar entry, and small recording overlay. No transcript history,
accounts, analytics, uploads, remote web content, or runtime plugin loading.
Explicit Copy keeps only the current result in memory until copied, dismissed,
replaced by a new session, or the app quits.

The first interface uses a left navigation rail and one content column, with a
large microphone control as the single visual emphasis. Use system UI fonts
for familiar desktop sizing, left-aligned labels, and consistent sentence case.
Tokens: background `#f6f8fc`, surface `#ffffff`, text `#172541`, secondary text
`#596983`, blue action `#285ddd`, divider `#dce3ef`. Model and permission states
are factual; no invented speed ratings or decorative dashboard statistics.

## Expanded unsigned preview

The owner approved the next stage and chose unsigned installers. Version
`0.2.0-preview.1` adds four portable Whisper profiles, English/Hindi selection
according to signed capabilities, custom words, app exclusions, launch at login,
indicator placement/scale, reviewed native settings import, resumable verified
downloads, sticky revocations and explicit post-restoration verification. The
worker receives custom words over stdin, not process arguments. Non-English text
is preserved without English command rewriting.

Exclusions use bundle identifiers on macOS, executable paths on Windows and X11.
Wayland exposes their unavailability. Both Linux modes retain explicit Copy.
The asynchronous Copy operation keeps pending text on failure and blocks a
second capture or duplicate Copy while the clipboard write is pending.

Supported portable models: small.en Q5_1, large-v2 Q5_0, large-v3 Q5_0 and
large-v3-turbo Q5_0. Apple-specific runtimes, Crisper conversion/runtime profiles,
other inference engines, speech enhancement, live transcription and diagnostics
export remain outside this preview. No full native-app parity is claimed.

## Verification on 2026-09-22

Baseline commit `e3095ad` passed the complete three-OS workflow:
https://github.com/Player0109/Textify/actions/runs/35684967292

| Check | Result |
| --- | --- |
| Native builds on macOS ARM64, Windows x64, Linux x64 | Passed baseline CI |
| Offline JFK recognition on all three platforms | Passed baseline CI |
| Fixture MediaStream through AudioWorklet, worker and Copy | Passed baseline CI; repeated locally for expanded code |
| Renderer isolation, settings, close-to-tray and packaged launch | Passed baseline CI |
| DMG, NSIS, AppImage and Debian package creation | Passed baseline CI |
| Expanded behavior/integrity/recovery/migration suite | 66 tests passed on all three CI runners |
| macOS owned-window insertion, clipboard restoration, target mismatch and password field | Passed native integration test |
| Physical microphone and actual application matrix | Pending |
| Installed Linux GNOME/KDE Wayland shortcut consent | Pending |
| Production signing/notarization | Deferred by owner; unsigned previews authorized |

Download the unsigned preview ZIP for your platform:

- [Windows x64 installer](https://github.com/Player0109/Textify/actions/runs/35687215578/artifacts/10676674220)
- [macOS ARM64 DMG](https://github.com/Player0109/Textify/actions/runs/35687215578/artifacts/10676953997)
- [Linux x64 AppImage and Debian package](https://github.com/Player0109/Textify/actions/runs/35687215578/artifacts/10676589444)

The expanded preview at commit `4c18c95` passed every job in run
[35687215578](https://github.com/Player0109/Textify/actions/runs/35687215578):
macOS ARM64, Windows x64 and Linux x64. Each job compiled the native workers,
ran the expanded checks and fixture recording flow, built the app/installer,
and launched the packaged output. Additional checks passed:

- Windows: native paste into an owned test window, original clipboard
  restoration, mismatched-target rejection, password-field rejection, silent
  NSIS installation and launch of the installed app.
- Linux: Debian installation and launch plus extracted AppImage launch under
  Xvfb. Normal FUSE mounting and installed Wayland portals still need desktop QA.
- macOS: read-only DMG mount and app launch from the disk image. Locally, the
  ad-hoc app also passed deep/strict signature verification.

The first expanded run passed macOS/Linux but its Windows test compared the
launcher PID with the browser PID. The corrected test compares the native target
with the Electron main-process PID; the subsequent Windows insertion test passed.
No production target validation was weakened.

Artifacts include `SHA256SUMS.txt` and installation notes. They are retained for
seven days; no GitHub Release was published. All four downloaded installer
checksums matched their CI manifests. Local downloaded copies are in
`electron/artifacts/preview-0.2/`. The branch is `codex/electron-cross-platform`.

Build output, sources downloaded for compilation, model fixtures, and screenshots
are excluded from Git. Runtime third-party notices and hook source are included
in the app resources. Existing Swift settings/models/sources remain untouched.

## Model fixture coverage

On the local Apple Silicon host, exact signed artifacts passed worker startup
with a custom-word prompt and public fixture recognition:

| Profile | Language and fixture | Result |
| --- | --- | --- |
| small.en Q5_1 | English, JFK sample through the capture/worker/Copy flow | Passed locally and on all three CI OSes |
| large-v2 Q5_0 | English, JFK sample | Passed locally |
| large-v3 Q5_0 | English, JFK sample | Passed locally |
| large-v3-turbo Q5_0 | English, JFK sample; Hindi, synthetic Lekha speech | Both passed locally |

Large-v2 was downloaded with the preview's real transfer implementation and
verified against the signed artifact size/hash. The Hindi test used synthetic
public text, not a physical microphone or natural-speech accuracy benchmark.
The large models still need Windows/Linux performance and real microphone QA.
No recognized text was retained in logs or written to transcript files.

## Remaining desktop checks

The owner will test Windows using `electron/MANUAL_QA.md`. Linux physical QA is
unassigned. Exercise GNOME and KDE Wayland plus X11: real microphone permissions,
global hold/release, cancellation, focus changes, password fields, rich clipboard,
quitting during capture/inference, tray behavior, multi-monitor indicator position
and launch at login. CI fixture and owned-window tests establish only their stated
conditions. No physical microphone or installed Wayland consent test is claimed.

## GPU-required correction (0.2.0-preview.2)

The owner requires GPU recognition on all three platforms and reports that the
Mac Right Command overlay disappears without inserting text. This supersedes
the previous CPU implementation on Windows/Linux. The updated worker uses Metal
or hardware Vulkan, rejects missing/unsupported GPUs, prevents CPU model graph
execution, and shows the GPU name or a bounded, actionable failure. The app
disables recording until the GPU model is ready. CPU audio preparation and token
sampling remain; they are not a CPU recognition fallback.

Local evidence: 73 tests pass, TypeScript/build passes, the native CPU-graph
refusal test passes, and both small.en and large-v3 recognize the public JFK
fixture on Apple M4 Max Metal. The installed Mac preview visibly reports that
GPU. All four model profiles, plus turbo Hindi, pass on local Metal. Real NVIDIA recognition remains pending.

The Mac symptom reproduced in an empty TextEdit document and also in the manual
Copy route, narrowing it to capture/recognition rather than only paste. The new
preview distinguishes missing PCM, silence, rejected recognition, and uncertain
insertion without recording audio or transcripts in diagnostics. The physical
microphone retest remains pending; do not call the original bug fixed yet.

The next physical test displayed “No speech detected.” System Settings showed
the built-in microphone selected at full input volume with a nonzero meter, but
Textify Electron was absent from the microphone privacy list. `codesign` revealed
that both the installed app and its helper lacked `com.apple.security.device.audio-input`.
The new package explicitly signs the app and helpers with this capability. A
package regression check failed against the installed build before the fix.
Physical microphone and insertion confirmation are still required after install.

Hosted macOS identifies “Apple Paravirtual device”; it lacks the Apple7 SIMD
features required by the pinned Metal kernels. It previously relied on CPU
fallback. The worker now checks Apple7 capability before declaring readiness.
All hosted runners check GPU refusal; local M4 Max fixtures provide GPU evidence.

The corrected bundle was installed into `/Applications/Textify Electron.app`
on 2026-09-22. The installed app and all Electron helpers pass the signed Audio
Input entitlement check and deep/strict code-signature verification. The former
bundle is retained under `electron/.native/installed-backups/`. System Settings
now lists Textify Electron with Microphone enabled, and Check microphone reports
permission available. The new ad-hoc signature requires refreshing the existing
Accessibility grant. This was completed by removing the stale Textify Electron
entry and adding `/Applications/Textify Electron.app` again; toggling the stale
entry alone was insufficient. The installed app now reports Hold Right Command
and Apple M4 Max / Metal readiness. Physical speech, Copy and TextEdit insertion
remain pending.
The local rerun passes 73 tests, TypeScript/build, the native GPU policy test and
the public English fixture on Metal.

### macOS native Quit correction

Cmd+Q reproducibly closed the installed settings window but left its main
process running, including with the global trigger disabled. A process sample
showed the main thread idle, not blocked in hook shutdown. An isolated JavaScript
`app.quit()` probe exited successfully and did not reproduce the native path.

The `before-quit` cleanup now resumes `app.quit()` with `setImmediate` after
cleanup completes. This lets the cancelled native quit callback return before
starting another quit. Electron's `Browser::Quit` assigns its quitting state
after `HandleBeforeQuit` returns; reentering it from a promise continuation in
that callback can otherwise have the new state overwritten by the cancelled
outer request. See the pinned [Electron implementation](https://github.com/electron/electron/blob/v44.4.3/shell/browser/browser.cc).

The rebuilt installed bundle passes Cmd+Q through the real macOS UI: the main
process and all helpers exit, verified by PID without reopening the app to
inspect it. This verifies idle native Quit; quitting during physical recording
still belongs to manual QA. A JavaScript-only quit smoke does not cover this
native callback timing. The 73 tests and TypeScript/build pass after the change.
The fixture capture-to-Copy smoke also passed during this continuation, without
touching the physical microphone or system clipboard.

The microphone/GPU correction at `5ed3143` passed all three jobs in
[run 35693514454](https://github.com/Player0109/Textify/actions/runs/35693514454),
including macOS signature/DMG checks and Windows/Linux installation checks.
That run precedes the native Quit timing follow-up above.

### Final continuation build and installers

Implementation commit `b8aa3f0` passed all macOS ARM64, Windows x64 and Linux x64
jobs in [run 35694007925](https://github.com/Player0109/Textify/actions/runs/35694007925).
This includes 73 tests per OS, GPU refusal on the hosted runners, packaged launch,
the macOS Audio Input signature check, installer creation and installation checks.
Local M4 Max Metal recognition and fixture capture/Copy are separate real-GPU
evidence. Actual NVIDIA and Linux hardware/Wayland tests remain pending.

Final unsigned preview downloads (the artifacts expire after seven days):

- [macOS ARM64 DMG](https://github.com/Player0109/Textify/actions/runs/35694007925/artifacts/10679493339)
- [Windows x64 installer for NVIDIA testing](https://github.com/Player0109/Textify/actions/runs/35694007925/artifacts/10680320520)
- [Linux AppImage and Debian package](https://github.com/Player0109/Textify/actions/runs/35694007925/artifacts/10679935877)

All four downloaded installer SHA-256 values match their CI checksum manifests.
Local copies are under `electron/artifacts/gpu-preview-b8aa3f0/`. No public release
was published. The locally rebuilt app is installed in Applications, retains
the user's existing Electron settings/models, and passes deep/strict signature
verification. Its `app.asar` SHA-256 is
`80a96c47e5338ac760d9295505a57409ec4206b61e6d7a82b328943f9a04c340`.
The microphone and Accessibility grants are present and Right Command is enabled.
The empty disposable TextEdit document is focused for the owner's spoken test;
no live speech or real-app insertion pass is claimed until that test returns.

## Native UI and additional Metal models — 2026-09-22

`0.2.0-preview.3` adopts the native Textify charcoal surfaces, blue selection,
waveform brand, typography and sidebar groups. The model browser groups the
signed artifacts into eight checkpoints with search, language/installed filters,
independently scrolling list and inspector, exact version actions, provenance
and license details. It does not display the Swift app's benchmark scores as
Electron measurements.

Apple Silicon adds eleven GGUF artifacts across Parakeet TDT 0.6B V3,
Qwen3-ASR 0.6B/1.7B and Confucius4-R2T2 1.7B. Existing Windows/Linux Whisper
support is retained. MLX/CoreML and Confucius live previews are outside this
slice; all four new families return final text on release. Qwen and Parakeet
support automatic language detection; Confucius exposes English and Chinese.
Replacement pairs work with all engines, while custom vocabulary prompts remain
Whisper-only.

Two checksum-pinned source builds produce separate static Metal executables,
with embedded shaders and only Apple system dynamic dependencies. Parakeet's
upstream CPU predictor/joint graph backends are changed to GPU backends. Its
encoder also uses the existing im2col/matmul depthwise path: the pinned Metal
backend cannot execute `CONV_2D_DW`, and the original runtime silently sent it
to CPU. A real fixture reproduced the refusal before this patch. Both
new ggml copies refuse direct, planned and scheduled CPU graph computation;
focused native tests exercise all three paths. Unsupported virtual Metal GPUs
are rejected before loading weights. The existing Whisper GPU policy remains.
Signed catalog and revocation checks still apply to every artifact. GGUF storage
retains `.gguf`, required by audio.cpp; Whisper's existing `.bin` paths remain
compatible. Regression coverage includes import/removal and source preservation.

Verified locally on the M4 Max:

- TypeScript, renderer build and all 82 unit tests pass.
- Qwen 0.6B Q8_0 and Qwen 1.7B BF16 recognize the public JFK speech fixture.
- Qwen 1.7B BF16 also recognizes the existing Hindi fixture.
- Confucius Q8_0 and F16 recognize the public JFK fixture.
- Parakeet Q8_0 recognizes the public JFK fixture, including a separate check
  using the signed worker inside the final installed application and imported model.
- Qwen 0.6B, Parakeet Q8_0 and Confucius Q8_0 pass the full fixture MediaStream → AudioWorklet →
  native GPU worker → explicit Copy path, without accessing the physical
  microphone or changing the system clipboard.
- Packaged app launches; microphone entitlements and deep/strict signature
  verification pass. All original preview settings and model files are preserved.
- The installed app reports microphone permission available. Its stale ad-hoc
  Accessibility entry was removed and the updated app re-added through System
  Settings; enabling the global trigger again reports “Hold Right Command”.

Five GGUF artifacts are verified and installed in Electron storage: Qwen 0.6B
Q8_0, Qwen 1.7B BF16, Parakeet Q8_0 and Confucius Q8_0/F16. The existing Swift
artifacts were copied without changing the originals; Qwen 0.6B and Parakeet
were downloaded from their signed catalog sources. The original Whisper model
is preserved. Qwen 0.6B Q8_0 is selected with English and Right Command enabled.
The previous installed app is retained under
`electron/.native/installed-backups/Textify Electron-before-model-ui-20260922T070400Z.app`.
The installed `app.asar` SHA-256 is
`5f9d4e9feb8028aafe88acc49e107d3c7c23d87398007ca9bca1e4bb49d60c2e`.
The installed transcribe worker SHA-256 is
`9ee8a297cec01f7bf3ba69608fe3368dcc1afc78aaca867a3dc7649bf2acd3cc`.
The owner was asked to try a physical Right Command dictation; no live insertion
pass is claimed without their result.

Implementation commit `87bc05c` passed all macOS ARM64, Windows x64 and Linux x64
jobs in [run 35698952276](https://github.com/Player0109/Textify/actions/runs/35698952276).
The run includes the 82 unit tests, CPU-fallback refusal checks, packaged launch,
installer creation and platform installation checks. Hosted-runner checks do not
replace the separate local M4 Max recognition evidence above or the pending
physical microphone and insertion check. The subsequent documentation commit
does not change the installed or tested implementation.

## Dock visibility correction — 2026-09-22

The earlier Finder pin did not fix running-app visibility. The recording overlay
called `setVisibleOnAllWorkspaces` with `visibleOnFullScreen: true`, which invokes
`DockHide` in the pinned Electron runtime and changes the entire app to accessory
mode. The installed process reported activation policy `1`, and a new launch
assertion reproduced `app.dock.isVisible() === false`.

The Mac overlay now uses a nonactivating panel and skips the process-type
transformation. This preserves its all-Spaces/fullscreen collection behavior
without hiding the application's Dock icon. See the
[pinned Electron implementation](https://github.com/electron/electron/blob/v44.4.3/shell/browser/native_window_mac.mm#L1339).

Verified startup Dock visibility, visibility with the main window closed and the
overlay shown, and reopening the same window through the Dock activation event.
The Qwen 0.6B fixture capture-to-Copy path, packaged launch, TypeScript and signed
microphone capability checks pass. The installed process now reports normal
activation policy `0`; the owner confirmed the blue T is visible in the bottom
Dock. The corrected application is pinned to `/Applications/Textify Electron.app`.
The existing Accessibility grant was refreshed, and the app reports GPU ready
and Hold Right Command after the update.

## Original BF16, realtime previews and compact overlay — 2026-09-22

`0.2.0-preview.4` adds the original NetEase Confucius4-R2T2 BF16 safetensors
checkpoint alongside GGUF Q8_0/F16. Eleven publisher files are pinned to Hugging
Face revision `185ce639118ad1362d049ca0d8ed04b6ec5cd6c9`, downloaded and locally
verified (4,092,092,714 bytes total). The additional catalog under `electron/models/`
has its own signature from the existing trusted key. The original Swift catalog
and implementation remain unchanged; both catalogs use the same verification and
sticky revocation rules. Directory downloads resume per file, hash every file,
and replace an existing installation only after the complete candidate verifies.

The initial BF16 fixture failed at model loading: the previous audio.cpp build
had no embedded model specification. GGUF carries its own specification, so it
had not exposed this packaging gap. Enabling the pinned runtime's deployment
build embeds the required metadata and makes original HF folders self-contained.
The original BF16 weights now run on Metal without Python, GGUF conversion or
CPU model fallback. Temporary diagnostic instrumentation was removed.

All three Confucius versions now emit incremental, in-memory text during capture.
The preview controller appends token deltas, rolls the decoder at 25 seconds,
bounds queued audio, and drains in-flight work before reset/cancellation. Final
recognition still uses the complete capture and inserts exactly once on release.
The floating panel follows the native 344×88-point shell, expanding to 344×156 for
three preview lines, with target identity, waveform and a subtle colored border.
Copy and dismissal remain available. The panel and skip-process-transformation
settings that fixed Dock visibility are preserved.

Local M4 Max evidence:

- TypeScript and all 93 tests passed, including directory integrity/recovery,
  directory revocations, preview cancellation, delta assembly and bounded windows.
- Native rebuild and GPU-only graph policy tests passed.
- Original BF16 passed English and Chinese streaming, stream finish/reset and
  final recognition. GGUF Q8_0 and F16 passed the same English streaming checks.
- A paced 32-second BF16 preview produced 57 updates, including 12 after the
  decoder reset. The first update arrived at 1.088 seconds including fixture audio
  arrival. This single public-fixture result is not a general latency benchmark.
- The full BF16 fixture MediaStream → AudioWorklet → preview → final recognition
  → overlay Copy path passed. Expanded-overlay bounds, transcript clearing,
  renderer isolation, settings persistence and Dock behavior passed. Public
  fixture screenshots are in `electron/artifacts/overlay-live.png` and
  `electron/artifacts/overlay-copy.png`; no personal audio or transcript was saved.
- Packaged launch, microphone entitlements and deep/strict signature checks passed.
  Installed `/Applications/Textify Electron.app`, imported BF16 through the verified
  directory installer, and selected **BF16 · Original**, English. The existing
  Accessibility grant was refreshed through Settings; Right Command is enabled.
  The running installed process remains in normal Dock activation policy `0` and
  the existing Applications Dock pin is preserved.
- The installed app initially failed its real microphone check despite the
  existing enabled grant. macOS TCC logs identified a stale code requirement
  after the ad-hoc signature changed. Resetting only this app's Microphone grant
  (`tccutil reset Microphone io.github.Player0109.Textify.Electron`) and renewing
  it restored capture; the installed UI now reports **Microphone permission is
  available.** No other app's permission or system security setting was changed.

The prior installed app is retained at
`electron/.native/installed-backups/Textify Electron-before-bf16-streaming.app`.
Installed `app.asar` SHA-256:
`b65f93fa6800d274c61f0aa4f63a5e0573078e184b76b6a0be406b3fe9c3e9ac`.
Installed audio worker SHA-256:
`e9021ed53f1e15815dd8a6df4d1e0fb7417f7d0a909dea139abb1bc594885a37`.
Owner confirmation of physical microphone dictation and real cross-app insertion
is still separate from these fixture checks. Windows/Linux runtime support for
Confucius remains outside this Mac implementation; no new remote CI pass is claimed.

## Floating bar reference correction — 2026-09-22

`0.2.0-preview.5` follows the owner's original Textify screenshots more closely.
The recording row has the native 34 rounded gray capsules across the full width,
with the native continuous waveform formula at up to 30 fps. Audio-level updates
do not restart or abruptly resize it. The extra Listening label and recording
close control are removed; Escape still cancels. The small coral voice mark stays
beside the Textify wordmark. Identity, signal and transcript spacing now follows
the native fixed 72/140-point panel body. Reduce Motion freezes the waveform.

The Mac target helper now returns the actual destination application's icon as
a bounded 48-pixel PNG. The session retains that icon alongside its original app
name, including during processing or Copy recovery. Manual dictation resets to
Textify. Icons remain in memory; no disk cache or external image request is used.
Only embedded image data is newly allowed by the renderer's image CSP.

Verification: all 94 tests, TypeScript/build, the Mac helper build, packaged
launch, signed microphone entitlements and deep/strict bundle validation passed.
The BF16 fixture capture → preview → recognition → Copy path passed, including
full-width gray waveform geometry, continuous motion, Reduce Motion, and native
icon PNG decoding/rendering. Screenshots were visually reviewed in
`electron/artifacts/overlay-live.png`, `overlay-app-icon.png`, and `overlay-copy.png`.

Installed at `/Applications/Textify Electron.app`; the existing Accessibility
and Microphone grants were refreshed after the ad-hoc signature changed. The
installed UI confirms GPU ready, Hold Right Command, and microphone permission
available. BF16/English and the Dock behavior are preserved. No new physical
speech or cross-app insertion verification is claimed by these fixture checks.

Installed `app.asar` SHA-256:
`53a37910cc470293141f29c5fad5c5d145a602642b4cf849702ecb872f7d7074`.
Installed Mac platform helper SHA-256:
`caf688f0b0ed7d685a21f75635f989d13815c20a95cb714f2033dfefdef3ebd8`.
Previous installed build:
`electron/.native/installed-backups/Textify Electron-before-overlay-refinement.app`.

## Animated transcript overflow — 2026-09-22

`0.2.0-preview.6` replaces the immediate `scrollTop` jump with a clipped
three-line viewport and a translated text layer. Layout observation moves that
layer only when wrapping changes its height, using the original Swift overlay's
140 ms ease-out transition. All visible lines move upward together; additional
tokens on the same line do not restart the movement.

The owner explicitly requested always-on animations and no Reduce Motion
control. The Electron overlay's motion checks and the app-wide reduced-motion
transition override were removed; macOS system preferences are unchanged.

All 94 tests, TypeScript and build checks passed. Renderer checks observed
intermediate positions and correct settling for three-to-four-to-five-line
wrapping, including an emulated reduced-motion system preference. The BF16
fixture capture, live preview, final recognition and Copy path also passed,
along with destination icons and Dock behavior. No physical speech or cross-app
insertion claim is added by these checks.

Installed and signature-verified `/Applications/Textify Electron.app`; refreshed
its existing grants after the ad-hoc signature change. The installed UI confirms
GPU ready, Hold Right Command, and microphone permission available. Installed
`app.asar` SHA-256:
`172a8dfa8c5fc92c72fc8cee532c18607e46e0ccaaa31be8c01b74c0e1e25d41`.
Previous installed build is retained at
`electron/.native/installed-backups/Textify Electron-before-transcript-animation.app`.

## Floating Icon settings — 2026-09-22

`0.2.0-preview.7` adds the native-style Floating Icon section to Dictation and
replaces the former numeric controls in General. A miniature display preview,
center/bottom guides, X/Y sliders, editable point values, arrow steppers, scale
from 50–200%, and Reset Position & Scale follow the supplied reference. Preview
updates during dragging; releasing saves through the existing settings path.
Keyboard edits, bounded numeric entry and resetting preserve other preferences.

Positive Y now moves the real bar up, matching native Textify and the preview.
Scaling and transcript expansion retain a fixed bottom anchor; the complete
window is clamped to the display's work area, including negative-origin displays
and small work areas. Existing scale/offset settings remain in the same schema.

All 98 tests and TypeScript/build checks passed. Full app checks covered dragging,
keyboard adjustment, numeric input, 5% scale steps, preview direction, persisted
values, reset, and the 780-point minimum window width. Screenshots in
`electron/artifacts/floating-icon-settings.png` and
`electron/artifacts/floating-icon-settings-compact.png` were visually reviewed.
BF16 fixture dictation, animated transcript overflow, native app icons, Copy and
Dock behavior also passed. No new physical speech/insertion result is claimed.

The packaged launch, microphone entitlements and deep/strict signature checks
passed. Installed `/Applications/Textify Electron.app`, retaining the prior
bundle at `electron/.native/installed-backups/Textify Electron-before-floating-settings.app`.
Installed `app.asar` SHA-256:
`4bf5a7b02441d69c2530711090b02ef50046218728fd8dbd2bc89dafba3ddb59`.
The installed UI confirms GPU ready, Hold Right Command and microphone permission
available after refreshing the existing grants. The new Floating Icon panel was
visually checked in the installed app; the owner's X 0 / Y 0 / 100% preferences
are preserved.

## Guided Accessibility setup — 2026-09-22

`0.2.0-preview.8` implements the owner's approved permission-flow improvements.
Dictation shows the Textify icon, two setup steps, Enable Accessibility, and live
required/waiting/granted status. Privacy retains the permission status after
setup. The native prompt and direct Settings link remain user initiated. A
one-second, five-minute-bounded poll detects approval while Settings is frontmost;
focus refresh catches later changes. Approval activates the existing shortcut
automatically in the normal app. Revocation stops the shortcut and cancels an
armed/recording session when detected, without proactively prompting.

The fallback reveals the actual running app bundle in Finder and displays its
exact path plus Settings +/Open instructions. Permission actions remain restricted
to the main renderer. No TCC reset/database change, new entitlement permission,
account, microphone recording or cross-app insertion is part of setup.

Packaging no longer hardcodes an ad-hoc identity. macOS `package`/`dist` require a
valid local Developer ID Application certificate/private key; ambiguous identity
selection requires `CSC_NAME`. Signed builds retain library validation. Explicit
`package:preview`/`dist:preview` commands preserve the local-preview path, and the
Electron CI workflow now uses those commands. Publishing is always disabled.
Optional notarization uses the existing electron-builder Keychain profile path;
no credentials are stored in the repo or bundle.

Validation: all 103 tests in 13 files, TypeScript and build passed. Existing app
smoke covered navigation, settings, transcript animation, native icon rendering
and Dock behavior. The new Accessibility smoke covered prompt deduplication,
Settings URL, automatic status detection, revocation, Finder path, narrow layout
and renderer authorization using substituted OS boundaries. It did not grant or
revoke real Mac permissions. Both permission UI screenshots were visually checked.
The explicit preview packaged successfully and passed deep/strict signature and
microphone-entitlement verification. Packaged `app.asar` SHA-256:
`fe32a83d531fea4e8e93c1ec205c8eec6fb54f5a275d47f750d54fdfa2d94aa2`.

Pending: this Mac reported zero valid signing identities. The signed command was
verified to fail with a clear certificate requirement rather than producing an
ad-hoc output. The owner replied that they are arranging Apple signing; signed
build, actual macOS approval/shortcut verification, and installation wait for
that certificate. `/Applications/Textify Electron.app` remains preview.7 with its
existing working grants. No current-user permission was changed in this slice.

## Simplified models page — 2026-09-22

`0.2.0-preview.9` implements the owner's simplified Electron model browser.
The compact list shows model names and language summaries, with Installed/In use
when applicable. The detail shows the name, full supported language list,
versions with download sizes and the appropriate action, followed by one
clickable upstream link. Import and Remove appear through each version's options
disclosure. Progress, pause/resume and integrity states remain actionable.
Provider, purpose, runtime names, descriptions, ratings, repeated captions and
the general model footnote are removed from this UI. Catalog verification,
license records, actual model support and inference behavior are unchanged.

The model link passes only a catalog ID through the existing main-only model
channel. The main process resolves its signed source and permits HTTPS without
embedded credentials. It does not accept arbitrary renderer URLs, enable window
navigation, or give the overlay link-opening access.

Validation: 103 tests in 13 files, TypeScript and production build passed. The
expanded existing UI smoke verifies source resolution, rejection of an arbitrary
URL as an ID, overlay isolation, search, version options and minimum-width
layout, alongside existing navigation/overlay/settings checks. Normal and compact
screenshots were visually reviewed. The separate Accessibility smoke passed
with substituted OS boundaries. Preview packaging, deep/strict signature,
microphone entitlements and installed packaged launch all passed.

Installed `/Applications/Textify Electron.app` as a local ad-hoc preview while
Apple Developer enrollment remains pending. Previous preview.7 is backed up at
`electron/.native/installed-backups/Textify Electron-before-models-preview9.app`.
Installed `app.asar` SHA-256:
`406f82aec5e197d500d2da7ce90fcdf10e33c919d960b6873b1e9320e47be42b`.
The installed page was visually verified with existing downloaded models and
Confucius BF16 in use. The stale Accessibility entry was refreshed for this
same application through System Settings, without changing other permissions.
After relaunch the UI reports GPU ready, Hold Right Command and microphone
permission available. Current X 0 / Y 0 / 80% preferences are preserved.
No new speech/insertion test or Developer ID signing/notarization is claimed.
This installation also includes the preview.8 guided Accessibility setup.

## Combined General page — 2026-09-22

`0.2.0-preview.10` removes native settings import, including its preview UI,
preload/IPC endpoint and now-unused converter. The three converter-specific
tests are removed; ordinary Electron preference upgrades remain covered.
The former Dictation page is now General and includes Launch at login below
the dictation preferences. The separate General sidebar entry/component is
removed; Floating Icon remains on the combined page. Model-file import and
existing settings are unchanged.

Validation: all 100 remaining tests, TypeScript, build, the existing UI smoke
and Accessibility smoke passed. The General screenshot was visually reviewed.
Completed preview packaging passed deep/strict signature and microphone
entitlement checks. Installed packaged launch and navigation passed.
Installed app.asar SHA-256:
`266eeb38e7d3dd295950c5fd61b3389a0cbd6a7466a622de27db5ea4a4a1a3c4`.
The previous bundle is preserved at
`electron/.native/installed-backups/Textify Electron-before-general-preview10.app`.
The existing Accessibility entry was refreshed through System Settings for the
updated local preview. Apple Developer ID signing remains pending.

## Simpler Privacy page — 2026-09-22

`0.2.0-preview.11` removes the non-interactive Audio and dictated text and
Clipboard settings rows. The introduction now states that speech is processed
on this device and no recordings or transcript history are saved. Clipboard
behavior remains documented in the Electron README. Permission controls and
app exclusions retain their existing behavior.

Validation: 100 tests, TypeScript, build and existing UI smoke passed. The
preview passed deep/strict signature and microphone entitlement checks, and
installed packaged launch/navigation passed. The installed Privacy page was
visually checked; both explanatory rows are gone and the remaining controls
fit without the previous long list.

Installed app.asar SHA-256:
`716fa6ea45577cc4570870bb539a6d9184623352ed247c1423257376e60ef636`.
Previous preview preserved at
`electron/.native/installed-backups/Textify Electron-before-privacy-preview11.app`.
The same application's existing Accessibility entry was refreshed through
System Settings. This remains a local ad-hoc preview; no new speech/insertion
test or Developer ID signing/notarization is claimed.

## Excluded apps card — 2026-09-22

`0.2.0-preview.12` presents Excluded apps in a rounded charcoal card matching
the neighboring permission sections. A blue app glyph, compact header and
right-aligned Add app action replace the loose heading and button. The picker,
empty state and saved app rows share the card; Cancel closes the picker and
successful saves return to the list. App identities and exclusion persistence
use the existing implementation.

Validation: TypeScript, production build and 100 existing tests passed. An
isolated run of the existing UI smoke with temporary app-list fixtures checked
empty/picker/populated layouts, add/remove persistence, and 780px layout without
horizontal overflow. Screenshots were visually reviewed. Preview packaging,
deep/strict signature, microphone entitlements and installed launch checks passed.
The installed Privacy card was visually checked on the user's Mac.

Installed app.asar SHA-256:
`75ef0b26d05d9c2d40e6805f66bfd2072c3c189cf14b2c4c640820f51283f878`.
Previous preview preserved at
`electron/.native/installed-backups/Textify Electron-before-exclusions-preview12.app`.
The same application's existing Accessibility registration was refreshed through
System Settings. This is a local ad-hoc preview. No new recording/insertion test
or Developer ID signing/notarization is claimed.

## Compact studio UI — 2026-09-23

`0.2.0-preview.13` applies the owner-selected compact studio design to General,
Transcription models, Floating Icon, Vocabulary, Privacy, guided Accessibility
setup, and the recording overlay. The sidebar and model browser use concise
rows; model details retain only languages, actionable versions with sizes, and
the upstream link. General groups its controls and places the Floating Icon
preview alongside its position and scale controls. Vocabulary uses two cards,
while Privacy aligns Accessibility, Microphone and Excluded apps in one panel.
The overlay keeps its destination app icon and three-line upward transcript
movement, with a gray waveform and restrained red/blue accents.

The redesign changes renderer presentation only. Model files and runtimes,
preferences, permissions, recording, insertion, and Dock policy are unchanged.
The UI smoke includes normal and 780px screenshots, navigation, model actions,
settings persistence, overlay animation and destination-icon checks. All 100
tests, TypeScript, build and UI smoke passed. The ad-hoc Mac preview passed
deep/strict code-signature and Audio Input entitlement checks, and the
installed bundle passed packaged launch, catalog and navigation smoke. Its
installed `app.asar` SHA-256 is
`49614c5e662585aed7508b885bc868e383c3c8d262ee7438d44798c2299fce6f`.
The previous app is backed up at
`electron/.native/installed-backups/Textify Electron-before-studio-preview13.app`.
The same app's stale ad-hoc Accessibility entry was removed and the installed
bundle re-added through System Settings after the owner approved Touch ID.
System Settings and Textify both show the grant as enabled. The installed
preview was visually checked on General, Models, Vocabulary, Privacy and
Floating Icon; it reports GPU ready, Right Command active and Confucius BF16
in use. The prior X 0 / Y 0 / 80% Floating Icon and Launch at login settings
remain saved. No new live microphone-to-insertion test or Developer ID signing
is claimed.
