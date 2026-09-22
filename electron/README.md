# Textify Electron preview

An Electron remake alongside the existing Swift application. The first release
targets macOS, Windows, and Linux. This directory currently provides the first
end-to-end preview; it does not yet replace all features of the native app.

## Run locally

Use Node.js 24, npm, CMake 3.20+, and a C++17 toolchain. On macOS install Xcode
Command Line Tools; on Windows use Visual Studio 2022 or newer with Desktop
Development with C++; on Linux use GCC or Clang and the desktop libraries listed
in `.github/workflows/electron.yml`. Build on the OS and architecture you package.

```sh
cd electron
npm ci
npm run native:prepare
npm run native:build
npm start
```

`native:prepare` explicitly downloads and verifies a pinned upstream whisper.cpp
archive. Compilation does not download source. JavaScript dependencies are
locked in `package-lock.json`.

Open **Models** and either download the English model or choose **Use existing
model file**. The exact artifact is `ggml-small.en-q5_1.bin` from the signed
catalog. Import copies the file into this app's own storage and verifies its
size and SHA-256. It never moves or changes a model used by the Swift app.

Hold the microphone button to record and release it to transcribe. Choose
**Copy dictation**, then paste into your app. Microphone permission is requested
when you record or use **Check microphone**.

## Desktop behavior

| Desktop       | Global trigger                                           | Text delivery                                                   |
| ------------- | -------------------------------------------------------- | --------------------------------------------------------------- |
| macOS         | Right Command by default, after Accessibility permission | Native paste with target revalidation and clipboard restoration |
| Windows       | Right Control by default                                 | Native paste with target revalidation and clipboard restoration |
| Linux X11     | Right Control by default                                 | Explicit Copy, then manual paste                                |
| Linux Wayland | Desktop GlobalShortcuts portal, when available           | Explicit Copy, then manual paste                                |

The microphone button always offers Copy. On Wayland, **Enable global trigger**
opens the desktop's shortcut consent flow; the desktop chooses the binding.
If the portal is unavailable or consent is denied, use the microphone button.
Wayland cancellation uses the recording indicator's Cancel button; Escape also
works while the settings window is focused.

Automatic paste checks that the originally captured app is still active and
rejects positively identified password fields. It does not restore app focus.
After a paste event has been sent, Textify does not retry an uncertain result.
It restores the previous clipboard only when the clipboard has not changed.
Explicit Copy replaces the clipboard normally.

The preview includes one English whisper.cpp model, replacement pairs, spoken
punctuation, a five-minute recording limit, tray/menu-bar operation, and a
recording indicator. Audio and pending dictation stay in memory. There is no
transcript history, telemetry, or speech upload. Downloads occur only after an
explicit model download action.

The application identity and data directory are **Textify Electron**, separate
from the Swift app. Model files and preferences are stored there. This preview
does not automatically migrate native-app settings.

## Verify and package

```sh
npm run check
npm run smoke
npm run package
```

`package` creates a local application directory under `release/`. `dist` creates
the configured DMG, NSIS, or AppImage/deb distribution for the current OS.
Packaging refuses native helpers built for a different OS or architecture.
The macOS preview uses an ad-hoc signature; release signing and notarization
are still required for public distribution.

To exercise actual offline recognition with the public speech fixture without
using your microphone or system clipboard:

```sh
TEXTIFY_MODEL_FIXTURE='/absolute/path/to/ggml-small.en-q5_1.bin' npm run smoke
node scripts/native-smoke.mjs '/absolute/path/to/ggml-small.en-q5_1.bin'
```

In PowerShell, set `$env:TEXTIFY_MODEL_FIXTURE` before running `npm run smoke`.
The optional smoke test copies the model into temporary isolated app storage,
feeds a fixture MediaStream through the real AudioWorklet and native worker,
checks Copy, and removes the temporary storage. Screenshots are written only
to the ignored `artifacts/` directory.

## Current verification and remaining work

Verified locally on Apple Silicon: 47 automated tests, TypeScript/build checks,
real fixture transcription through the native worker and audio capture path,
renderer isolation, settings persistence, and close-to-tray behavior.
The packaged Mac app also passes launch/catalog/navigation checks and
`codesign --verify --deep --strict`. To repeat the packaged launch check:

```sh
node scripts/packaged-smoke.mjs 'release/mac-arm64/Textify Electron.app/Contents/MacOS/Textify Electron'
```

This read-only launch check uses the packaged app's normal data directory;
it does not request recording, download a model, or paste text.

The CI workflow builds/tests/packages macOS ARM64, Windows x64, and Linux x64.
The workflow has not been run remotely during this implementation. Actual
Windows/Linux behavior, physical microphones, global keys, cross-app insertion,
clipboard restoration, and installed Wayland portal consent remain release
gates. Local macOS checks do not establish those results.

Full model-catalog and runtime parity, language selection, custom words,
exclusions, launch-at-login, download resume, persistent revocations,
diagnostics, updates, and distribution signing remain to be migrated. See
`../docs/implementation/electron-migration.md` for the migration scope.
