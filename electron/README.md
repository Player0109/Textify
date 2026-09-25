# Textify desktop preview

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

Open **Transcription models** to search, download or import an exact signed
model artifact. Each model shows its supported languages, versions and sizes,
installation status, and an upstream model link. Search, language and installed
filters narrow the list. A version's options button reveals Import and Remove.
All platforms support Whisper small.en, large-v2, large-v3, and large-v3-turbo.
The first three expose English; turbo exposes English and Hindi according to
the bundled signed catalog. Import copies into this app's own storage and
checks size and SHA-256. It never changes a model used by the Swift app.

Apple Silicon also supports these GPU-only versions:

| Checkpoint | Versions | Runtime |
| --- | --- | --- |
| Parakeet TDT 0.6B V3 | GGUF F16, Q8_0, Q5_K_M | transcribe.cpp |
| Qwen3-ASR 0.6B | GGUF BF16, Q8_0, Q5_K_M | transcribe.cpp |
| Qwen3-ASR 1.7B | GGUF BF16, Q8_0, Q5_K_M | transcribe.cpp |
| Confucius4-R2T2 1.7B | GGUF Q8_0, F16; original BF16 safetensors | audio.cpp |

Confucius shows live English or Chinese text in the compact floating bar while
recording. All models perform final recognition on release and insert once.
The bar follows native Textify's app identity, waveform, colored border and
three-line transcript, with compact Copy and dismissal controls for recovery.
Qwen and Parakeet offer automatic language detection. Native MLX/CoreML variants
are not included. Custom vocabulary prompts apply
to Whisper; replacement pairs apply to every engine. New family support on
Windows/Linux is deferred. Native app ratings are not claimed for Electron.

**BF16 · Original** downloads the publisher's 11 original files (4.09 GB) from
`netease-youdao/Confucius4-R2T2` revision
`185ce639118ad1362d049ca0d8ed04b6ec5cd6c9`. **Import folder** accepts an existing
copy of that exact revision. Files are staged, individually hashed and installed
as a complete directory; partial transfers can resume. Extra source files are
not imported. The entry is in `models/manifest.json` inside this Electron directory,
signed with the existing trusted catalog key. Both catalogs are verified and all
files remain subject to sticky revocations, including canonical directory digests.
The root Swift catalog is unchanged. Model weights remain BF16; there is no
Python service, runtime conversion to GGUF, cloud ASR or CPU inference fallback.

The extra source archives are checksum-pinned. They build offline as separate
executables with embedded Metal shaders and no non-system dylibs. audio.cpp's
deployment build also embeds model specifications required by original HF folders.
Parakeet's
predictor/joint graphs are moved to Metal, and each ggml copy rejects CPU graph
execution. GPU-less Mac CI also checks both additional workers refuse startup.

Streaming uses 320 ms chunks and bounded 25-second decoder windows, independent
of the complete five-minute capture retained for final recognition. Cancel and
release drain in-flight preview work before reset; late text cannot enter another
session. If inference falls behind, only stale preview audio is discarded. Audio
and preview text are held in memory, cleared after the session and never logged.

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

The preview includes custom words, replacement pairs, English spoken
punctuation, a five-minute recording limit, tray/menu-bar operation, adjustable
recording indicator, language selection, model switching/deletion, resumable
downloads, and persistent signed revocation rules. Non-English dictation skips
English text rewriting. Restored model artifacts require explicit verification.

**General → Floating Icon** provides a live position preview, X/Y sliders and
point values, 50–200% scale, arrow steppers, and Reset Position & Scale. Positive
Y moves the bar up. The bar remains inside the active display's visible area;
dragging previews immediately and saves on release.

**General** combines dictation preferences, Floating Icon and launch at login
after installation. **Privacy** offers app
exclusions on macOS, Windows,
and X11; Wayland cannot reliably identify foreground apps and shows exclusions
as unavailable. On any desktop, the in-app microphone button is an explicit
Copy workflow and does not inspect another app.

Audio and pending dictation stay in memory. Activity stores only daily numeric
totals for completed dictations, with day, week, and month views derived from
those totals. There is no transcript
history, telemetry, or speech upload. Model downloads require an explicit action.
Custom words, preferences, model files and trust records remain in the existing
**Textify Electron** data directory so preview updates retain them.

## Verify and package

```sh
npm run check
npm run smoke
npm run package
```

`package` creates a local application directory under `release/`. `dist` creates
the configured DMG, NSIS, or AppImage/deb distribution for the current OS.
Packaging refuses native helpers built for a different OS or architecture.
On macOS these commands require a valid **Developer ID Application** certificate
and its private key in the local Keychain. If there are several, set `CSC_NAME`
to the intended certificate name. Keep the same signing identity and bundle ID
across updates so macOS can recognize existing permission grants. The signing
path does not silently fall back to ad-hoc signing. It retains library validation
and signs the app and its embedded code with the selected identity.

Until a certificate is available, `npm run package:preview` and
`npm run dist:preview` explicitly produce local ad-hoc previews. These can require
permissions to be renewed after an update. Electron CI uses these preview
commands; Windows installers remain unsigned. No packaging command publishes.
For notarization, configure electron-builder's `APPLE_KEYCHAIN_PROFILE` with an
existing local notarytool credential profile before packaging. Production Mac
packaging refuses to run without notarization credentials. Verify the resulting
app's ticket and Gatekeeper assessment before distribution; signing alone does
not claim a notarized release, and credentials are never bundled.

### Accessibility setup on macOS

General shows **Enable Accessibility** when permission is missing. The button
requests the native prompt and opens the matching settings pane. Turn on the
exact app name shown in the card; Textify checks once per second for up to five
minutes, then also checks when its window regains focus. Approval automatically
activates the global shortcut, while Privacy shows **Enabled**. No extra trigger
activation click is required in the normal path. Revocation never prompts on
its own; it stops the shortcut and any active recording when detected.

If Textify is absent from the list, a small floating helper appears over
Settings. Drag its Textify icon into the Accessibility app list, then turn on
the new switch. The helper drags the exact running `.app` bundle and closes
when approval is detected; it can also be dismissed manually.

**App missing, or already switched on?** reveals the exact running `.app` path,
a Finder shortcut and instructions for adding that copy through the Settings
**+** button if dragging is unavailable. The app never edits TCC databases, grants itself access, resets
permissions or changes other apps' grants. Permission status is read from macOS,
not saved as a preference. `node scripts/accessibility-smoke.mjs` checks this
flow with substituted OS boundaries and isolated app data; it does not change
actual Mac permissions.

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

The baseline passed native builds, 47 tests, real fixture transcription,
Electron smoke, packaged launch and installer creation on all three CI runners:
[baseline run](https://github.com/Player0109/Textify/actions/runs/35684967292).
The expanded preview passes 101 tests locally; its workflow repeats those checks
and adds installation/launch checks for NSIS, Debian, extracted AppImage and DMG.
See the [migration record](../docs/implementation/electron-migration.md) for the
latest run, tested revision and downloadable artifacts.
The [desktop release procedure](RELEASING.md) lists the checks required before
a public cross-platform download is created.

On macOS, `node scripts/insertion-smoke.mjs` verified native insertion into an
owned test window, original clipboard restoration, target mismatch rejection,
and password-field rejection. The script uses public test text and no microphone;
Windows CI also runs it. Physical microphone, real app, login startup and Linux
GNOME/KDE Wayland checks remain in [MANUAL_QA.md](MANUAL_QA.md). The owner can test
Windows; a Linux desktop tester is still needed. Xvfb is not a Wayland desktop.

The portable preview does not yet include all of the Swift app's inference
engines, speech enhancement, or diagnostics export. Confucius4-R2T2 provides
live transcription previews on macOS. No full native-app parity or production
readiness is claimed.

For additional local model checks, `scripts/runtime-smoke.mjs` verifies the signed
model hash and exercises language and custom-word configuration with public test
audio. It accepts `MODEL [en|hi] [mono-16khz-f32-file]`; English defaults to the
public JFK sample. No recognized text is logged or saved.

## GPU-required preview

`0.2.0-preview.2` supersedes the CPU-based Windows/Linux preview. Metal is
required on macOS; Windows and Linux build with `GGML_VULKAN=ON`. For Windows
builds install the Vulkan SDK (headers, libraries and glslc); Ubuntu builds need
`libvulkan-dev glslc`. End users need their hardware vendor's GPU driver, not
the SDK. Linux also requires the system Vulkan loader (`libvulkan1`).

`native/require-gpu.mjs` applies exact edits to the checksum-pinned whisper
source: GPU backend initialization must succeed, model weights must use GPU
buffers, and the graph scheduler refuses CPU computation. Software/virtual
Vulkan devices are rejected. Audio preprocessing, token sampling, memory
transfers and graph bookkeeping still use the CPU. The native build runs a
regression test that attempts a CPU matrix graph and requires refusal.

On all hosted CI runners, no-GPU startup and disabled recording are tested.
The hosted Mac exposes a paravirtual Metal device without Apple7 compute features.
These checks are not evidence of NVIDIA/AMD/Intel GPU recognition or performance;
those require a real GPU. The local Mac fixture uses real Metal.

Holds without usable audio and rejected or empty recognition return quietly to
idle. Capture, model, and insertion failures still show actionable errors.
The Mac package now explicitly includes the Audio Input entitlement on the app
and helpers. `mac-signature-smoke.mjs` verifies the signed output; the earlier
unsigned package lacked this capability even though it declared a usage string.

Parakeet GPU regression check (Apple Silicon, exact signed Q8_0 file):

```sh
node scripts/runtime-smoke.mjs /path/to/parakeet-tdt-0.6b-v3-Q8_0.gguf
TEXTIFY_MODEL_ID=parakeet-tdt-0.6b-v3-q8-0 TEXTIFY_MODEL_FIXTURE=/path/to/parakeet-tdt-0.6b-v3-Q8_0.gguf npm run smoke
```

The pinned Parakeet encoder otherwise selects `CONV_2D_DW`, unsupported by its
Metal backend, and silently schedules it on CPU upstream. The preparation patch
selects the existing im2col/matmul implementation for both depthwise sites;
Textify's CPU refusal remains enabled. This is separate from moving its TDT
decoder graphs onto the GPU. Recognition is tested with the public JFK fixture,
without saving the transcript.
