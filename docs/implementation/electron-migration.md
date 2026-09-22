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
| Expanded behavior/integrity/recovery/migration suite | 66 tests passed locally |
| macOS owned-window insertion, clipboard restoration, target mismatch and password field | Passed native integration test |
| Physical microphone and actual application matrix | Pending |
| Installed Linux GNOME/KDE Wayland shortcut consent | Pending |
| Production signing/notarization | Deferred by owner; unsigned previews authorized |

The expanded workflow repeats builds/tests and adds actual NSIS/Debian
installation, extracted AppImage launch, mounted DMG launch and Windows native
insertion checks. Its final run and artifacts will be recorded here after the
checks finish. Outputs are CI artifacts with seven-day retention; no GitHub
Release is published. The Electron branch is `codex/electron-cross-platform`.

Build output, sources downloaded for compilation, model fixtures, and screenshots
are excluded from Git. Runtime third-party notices and hook source are included
in the app resources. Existing Swift settings/models/sources remain untouched.

## Remaining desktop checks

The owner will test Windows using `electron/MANUAL_QA.md`. Linux physical QA is
unassigned. Exercise GNOME and KDE Wayland plus X11: real microphone permissions,
global hold/release, cancellation, focus changes, password fields, rich clipboard,
quitting during capture/inference, tray behavior, multi-monitor indicator position
and launch at login. CI fixture and owned-window tests establish only their stated
conditions. No physical microphone or installed Wayland consent test is claimed.
