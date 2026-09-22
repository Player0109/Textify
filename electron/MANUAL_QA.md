# Textify Electron desktop checks

These checks distinguish actual desktop behavior from automated fixture tests.
Use a fresh unsigned preview installer. Record the app version, OS version,
desktop environment (on Linux), microphone, and pass/fail for each row.

The owner is testing Windows. A Linux desktop tester is still needed. The
automated Linux checks use Xvfb and do not establish GNOME/KDE Wayland behavior.

## Windows quick start

1. Download the Windows artifact ZIP from the successful Electron workflow run,
   extract it, and run `Textify-Electron-…-win-x64.exe`. The preview is unsigned.
2. Open Textify, choose Models, and download Whisper small.en or import the exact
   signed model file. Allow microphone access when starting the first recording.
3. Hold Textify's microphone button, speak a sentence, release, choose Copy, and
   paste into Notepad. Confirm the sentence appears once.
4. Enable the global trigger. Focus Notepad, hold Right Control, speak, and
   release. Confirm automatic insertion appears once in Notepad.

## Core behavior

| Check | Expected result | Result |
| --- | --- | --- |
| Short accidental trigger tap | No text, no lingering recording | Pending |
| Silence | No invented text | Pending |
| Hold, speak, release | One completed result | Pending |
| Escape during recording | Capture ends, no insertion | Pending |
| Microphone button, then Copy | Clipboard changes only after Copy | Pending |
| Close settings window | Tray utility remains; reopening works | Pending |
| macOS Cmd+Q while idle | Main process and helpers exit; next launch opens normally | Passed locally on 2026-09-22 after native quit timing fix |
| Quit during recording or recognition | Mic stops; no delayed insertion | Pending |
| Five-minute cap | Recording stops and produces at most one result | Pending |

## Permissions, focus, and clipboard

Use test text only. For focus checks, have Notepad and a browser test field open.

| Check | Expected result | Result |
| --- | --- | --- |
| Deny microphone permission | Actionable failure; no stuck recording | Pending |
| Unplug selected microphone during capture | Recording stops; retry can use a newly selected device | Pending |
| Select a missing microphone | No silent switch to another microphone | Pending |
| Change foreground app before recognition finishes | No automatic paste into the newly focused app | Pending |
| Focus a password field | Global recording/insertion is rejected when the field is identified as secure | Pending |
| Clipboard initially contains plain text | Previous text restored after automatic paste | Pending |
| Clipboard initially contains HTML/rich text or an image | Clipboard preserved, or explicit Copy offered if safe restoration is unavailable | Pending |
| Copy unrelated text while recognition is running | User's newer clipboard contents are preserved after paste | Pending |
| Exclude Notepad, then use global trigger there | Microphone does not start | Pending |

## Models and settings

| Check | Expected result | Result |
| --- | --- | --- |
| Pause download, quit, reopen, Resume | Valid partial bytes are reused and final checksum is checked | Pending |
| Import incorrect model bytes | Import rejected; existing model remains usable | Pending |
| Install two models and choose Use | Selection persists after relaunch | Pending |
| Remove active model | Dictation becomes unavailable until a model is selected | Pending |
| Add custom word and replacement pair | Saved across relaunch; replacement remains literal | Pending |
| Choose Hindi with Whisper large-v3-turbo | Hindi text is preserved without English punctuation-command rewriting | Pending |
| Import native settings JSON | Preview shown before Apply; original file unchanged | Pending |
| Enable/disable Launch at login | Registration matches choice on next sign-in | Pending |
| Change indicator position/scale | Indicator stays within the screen on different monitors | Pending |

## Linux desktop checks

Repeat on GNOME Wayland, KDE Wayland, and X11. Record the desktop version.

- Enable global trigger and accept the desktop shortcut dialog. Hold and release
  the assigned shortcut; confirm a single recording and a Copy result.
- Deny shortcut consent or use a desktop without GlobalShortcuts. Confirm the
  microphone button still works and no automatic paste is attempted.
- Cancel from the recording indicator while another app is focused.
- Use Copy, focus the intended app, and paste manually.
- On Wayland, app exclusions must be shown as unavailable because Textify cannot
  reliably identify the foreground app. On X11, test a configured exclusion.
- Install/relaunch the AppImage or Debian package and recheck shortcut consent,
  tray reopening, and launch-at-login behavior.

## Current evidence

The first CI preview passed native compilation, offline fixture transcription,
Electron smoke, packaged launch, and installer creation on all three OSes:
https://github.com/Player0109/Textify/actions/runs/35684967292

This does not mark any pending physical-desktop row above as passed. Later
feature builds must repeat CI and record their commit and artifact versions.

## GPU-required preview regression checks

- [ ] Windows NVIDIA: GPU name is shown after loading the model; public phrase
  is recognized on Vulkan with acceptable latency. Repeat each supported model.
- [ ] Linux hardware Vulkan: confirm GPU name and recognition; software-only
  Vulkan and missing drivers must refuse dictation.
- [ ] Insufficient GPU memory or unsupported GPU operations show an error;
  no CPU inference and no automatic model downgrade occur.
- [ ] Mac real microphone: hold Right Command in TextEdit, dictate a public
  phrase, release, and verify insertion. Record any displayed failure reason.

## Additional models and native visual design (September 22)

- [x] Native-style dark sidebar, checkpoint browser and inspector reviewed in screenshots.
- [x] Installed app selects and loads Qwen3-ASR 0.6B Q8_0 on Metal through the UI.
- [x] Installed microphone permission check succeeds after upgrade.
- [x] Re-added the updated app's Accessibility entry; global trigger reports Hold Right Command.
- [x] Public fixture recognition: Qwen 0.6B Q8_0, Qwen 1.7B BF16 (English/Hindi), Parakeet Q8_0, Confucius Q8_0/F16.
- [x] Fixture capture-to-copy pipeline: Qwen 0.6B, Parakeet Q8_0 and Confucius Q8_0.
- [x] Final installed, signed Parakeet worker recognizes the public fixture using the imported model.
- [ ] Owner's physical speech and insertion check with the updated model selection.

New families currently use Metal on Apple Silicon. No MLX/CoreML variants or
Confucius live previews are claimed for this Electron build.

Implementation `87bc05c` passed all three OS jobs, including packaged launch and
installer checks: https://github.com/Player0109/Textify/actions/runs/35698952276
This automated evidence does not mark the pending physical-desktop checks passed.

## Dock visibility correction (September 22)

- [x] Reproduced hidden Dock state caused by fullscreen-overlay process transformation.
- [x] Regression checks: visible after launch, stays visible with settings closed
  and overlay shown, Dock activation reopens the same settings window.
- [x] Corrected packaged application installed; process activation policy is regular.
- [x] Owner confirmed the new blue T icon is visible in the bottom Dock.
- [x] Qwen 0.6B fixture capture-to-Copy still passes; Right Command reports ready.
