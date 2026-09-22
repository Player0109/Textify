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

## Release gates and later migration

Verify microphone revocation/disconnection, global hold/release, cancellation,
focus changes during recognition, password fields, rich clipboard restoration,
and quitting during capture/inference on actual target desktops. Exercise
GNOME and KDE Wayland plus X11; portal support varies by desktop/version.
Package identity and portal consent must be tested after installation.

Port the remaining catalog runtimes, full vocabulary/custom-word behavior,
language choices, exclusions, launch-at-login, overlay placement, diagnostics,
download resume, revocation persistence, and model lifecycle parity only after
the first path is stable. No full native-app parity or production readiness is
claimed by this milestone. macOS signing/notarization and Windows signing are
separate release work.

## Verification on 2026-09-22

| Check | Result |
| --- | --- |
| TypeScript, production renderer/main build | Passed on macOS ARM64 |
| Automated behavior/integrity/lifecycle/portal tests | 47 passed |
| Native whisper.cpp worker, public JFK fixture | Passed, PCM and output held in memory |
| Fixture MediaStream → AudioWorklet → native worker → explicit Copy | Passed; microphone and system clipboard were not used |
| Renderer isolation and IPC authorization | Passed in Electron smoke |
| Settings persistence and duplicate rejection | Passed in Electron smoke |
| Window close leaves tray utility running | Passed in Electron smoke |
| Packaged Mac app launch, catalog verification, navigation | Passed |
| Mac package ad-hoc signature, deep/strict verification | Passed |
| Native worker macOS deployment target | 14.0 |
| Production npm dependency audit | No vulnerabilities reported |
| Windows/Linux native builds and desktop behavior | Not run locally |
| GitHub Actions three-OS workflow | Configured; not run remotely |

The local app is `electron/release/mac-arm64/Textify Electron.app`.
Build output, downloaded sources, models used as test fixtures, and screenshots
are excluded from Git. Runtime third-party notices and hook source are included
in the application resources.

The preview implements automatic insertion helpers for macOS and Windows, but
those helpers still require real cross-app testing. No physical microphone,
password-field, focus-switch, clipboard restoration, or installed Wayland
desktop test is claimed. Linux X11 and Wayland both use explicit Copy in this
milestone, including when global shortcuts are available.
