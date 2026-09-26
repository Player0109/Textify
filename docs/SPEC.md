# Textify desktop specification

Current scope: September 27, 2026.

Textify is an Electron desktop dictation utility for macOS, Windows, and Linux.
The previous Swift macOS application has been retired. The remaining Swift
package supports signed-catalog maintenance and verification; it does not build
an application.

## Product behavior

Hold the microphone button or an available global trigger, speak, and release.
Textify records in memory, transcribes with a local GPU worker, applies the
selected text rules, and delivers one final result. Recording has a five-minute
limit. Confucius4-R2T2 additionally supports an in-memory live preview.
This is a dictation utility, not a transcript-history or file-transcription
workspace.

The app provides a persistent settings window, tray/menu-bar access, a floating
recording bar, model management, microphone selection, vocabulary, replacement
pairs, and local numeric Activity views. Closing the settings window leaves the
app running. Updates are installed manually from GitHub Releases.

## Platforms and delivery

| Platform | Runtime requirement | Global trigger | Text delivery |
| --- | --- | --- | --- |
| macOS 14+, Apple Silicon | Metal | Right Command by default; Accessibility permission | Validated native paste or explicit Copy |
| Windows x64 | Hardware Vulkan GPU and compatible driver | Right Control by default | Validated native paste or explicit Copy |
| Linux x64, X11 | Hardware Vulkan GPU and compatible driver | Right Control by default | Explicit Copy and manual paste |
| Linux x64, Wayland | Hardware Vulkan GPU and compatible driver | Desktop GlobalShortcuts portal when available | Explicit Copy and manual paste |

CPU-only inference and software Vulkan devices are not supported. CPU work for
capture, preprocessing, token sampling, and runtime bookkeeping still occurs.
The microphone button always uses the explicit Copy workflow. It does not
inspect another app or require a global shortcut. App exclusions are available
on macOS, Windows, and X11; Wayland cannot reliably identify foreground apps.

Automatic paste revalidates the original target, rejects positively identified
password fields, and does not restore app focus or retry an uncertain paste.
Clipboard restoration occurs only if the clipboard has not changed. Explicit
Copy replaces the clipboard normally.

The desktop application keeps bundle identity
`io.github.Player0109.Textify.Electron` and its existing **Textify Electron** data
directory across updates. Retiring the old application does not migrate,
modify, or remove any installed application or user data.

## Models and trust

The desktop app selects supported exact artifacts from the signed base catalog
in `models/`, plus its signed supplement in `electron/models/`. A catalog entry
alone is not a promise of desktop support. The supported subset is defined by
`electron/src/main/models.ts` and documented in the
[desktop model guide](../electron/README.md).

Whisper small.en, large-v2, large-v3, and large-v3-turbo, and selected Parakeet
TDT, Qwen3-ASR, and Confucius4-R2T2 artifacts, are available on all three
platforms. Languages and import formats follow each signed
artifact's capabilities. Imports copy and verify exact supported artifacts;
arbitrary custom model files and runtime plugins are not supported.

Model weights are downloaded separately after an explicit user action. Exact
file sizes and SHA-256 values must match the trusted signed metadata before
activation. Download sources are immutable Textify release assets or exact
commit-pinned public Hugging Face files. Interrupted transfers may resume.
Signed revocations remain enforced locally; restoration requires explicit
verification before an artifact can be used again.

The catalogs, detached signatures, and revocation inputs are bundled. Launching
the app or opening settings does not fetch a catalog or revocation feed. Catalog
changes require a new app release. Private signing keys and notarization
credentials never belong in the repository or CI.

Whisper supports custom vocabulary prompts. Replacement pairs apply to every
engine, and English spoken-punctuation rewriting is skipped for non-English
dictation. Speech enhancement and diagnostics export are not desktop features.

## Privacy and Activity

Audio and pending dictated text stay in memory. The app has no accounts,
telemetry, cloud speech recognition, or transcript history. Preferences,
vocabulary, model files, trust records, and Activity totals remain local.
Explicit model downloads and user-opened source links require network access.

Activity stores only daily word count, dictation count, recording duration, and
estimated time saved, with day/week/month views. It stores no dictated text,
audio, or destination app. The time-saved estimate uses a 40-words-per-minute
typing baseline and does not measure later editing. There is no Activity reset
control. See [PRIVACY.md](../PRIVACY.md) for the privacy statement.

## Architecture and maintenance

- `electron/src/core/`: dictation lifecycle and pure behavior.
- `electron/src/main/`: trusted model storage, local worker supervision,
  permissions, narrow IPC, and desktop integration.
- `electron/src/renderer/`: settings, recording overlay, and isolated audio
  capture. Renderer pages are sandboxed with context isolation.
- `electron/native/`: native GPU workers and OS integration helpers.
- `electron/tests/` and `electron/scripts/`: behavior checks, isolated smoke
  tests, packaging, signing, and artifact validation.
- `script/models/` and the root Swift package: catalog signing and verification
  tools retained independently of the removed application.

Catalog provenance, licenses, signed bytes, and historical benchmark evidence
remain reviewable. Historical ratings do not establish Electron performance or
support. See [catalog provenance](models/curated-models.md),
[signature format and tooling](models/model-manifest-signing.md), and
[catalog release rules](models/catalog-publication-and-rollback.md).

## Verification and distribution

Use the [desktop development guide](../electron/README.md),
[release procedure](../electron/RELEASING.md), and
[physical-desktop QA checklist](../electron/MANUAL_QA.md).
Automated checks cover behavior, isolated fixture capture, packaging, launch,
and no-GPU refusal. They do not replace physical microphone, permission,
global-shortcut, hardware-GPU, or Wayland testing.

Mac production artifacts require Developer ID signing, notarization, stapling,
and Gatekeeper validation. Windows/Linux preview installers remain unsigned.
Generate checksums from the final distributable bytes. Packaging never publishes
by itself, and unfinished physical-platform checks remain explicit in preview
release notes.

## Repository policy

The application is Apache-2.0; each dependency and optional model retains its
own license. Bug reports, feature requests, and model suggestions use GitHub
Issues. External pull requests are not accepted under the current
[contribution policy](../.github/CONTRIBUTING.md). Report vulnerabilities through
[private security reporting](../.github/SECURITY.md).
