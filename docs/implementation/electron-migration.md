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
