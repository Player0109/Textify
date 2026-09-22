# Textify Electron unsigned preview

Version 0.2.0-preview.1. This is a testing build, separate from native Textify.
No speech models are bundled. After installation, choose Models to download or
import a verified model. Use the microphone button, release, then Copy and paste
for the first test. Audio is processed locally.

## Windows x64

Extract the artifact ZIP and run `Textify-Electron-…-win-x64.exe`. The installer
is unsigned; if Windows shows SmartScreen, check the repository/artifact source
and checksum before choosing More info → Run anyway. Managed device policies
may prevent installation. Do not disable system-wide protection.

Verify the checksum against `SHA256SUMS.txt` in PowerShell:

```powershell
Get-FileHash .\Textify-Electron-*-win-x64.exe -Algorithm SHA256
```

Enable the global trigger in Textify, focus Notepad, and hold Right Control to
dictate. Check that release inserts text once. The app uses normal user
permissions; elevated target apps may not accept automatic insertion.

## macOS 14+ / Apple Silicon

Open the DMG and drag Textify Electron into Applications before enabling launch
at login. This app is ad-hoc signed, without Developer ID or notarization.
If Gatekeeper blocks opening, use System Settings → Privacy & Security → Open
Anyway for this app after checking its source and checksum. Do not disable
Gatekeeper globally. Allow microphone and Accessibility access when requested.
Right Command is the default global trigger.

```sh
shasum -a 256 Textify-Electron-*-mac-arm64.dmg
```

## Linux x64

On Debian/Ubuntu, install the `.deb` with:

```sh
sudo apt install ./Textify-Electron-*-linux-amd64.deb
```

For AppImage, move the file to a permanent location, make it executable, and
launch it. Launch at login refers to this path. An AppImage-capable desktop with
FUSE is required for normal mounting; environments without FUSE can extract it
with `--appimage-extract` and launch `squashfs-root/AppRun` instead.

```sh
chmod +x Textify-Electron-*-linux-x86_64.AppImage
sha256sum -c SHA256SUMS.txt
```

Linux always uses explicit Copy and manual paste. On Wayland, Enable global
trigger requests a desktop shortcut through GlobalShortcuts. If that desktop
lacks the portal or consent is denied, use Textify's microphone button. App
exclusions are unavailable on Wayland. The automated Linux checks use Ubuntu
24.04 and Xvfb; real GNOME/KDE Wayland and microphone testing remain pending.

## Test and remove

Follow `electron/MANUAL_QA.md` in the repository for the desktop test matrix.
Please report app/OS version, steps and pass/fail, without private dictated text.
Windows testing is assigned to the owner; a Linux desktop tester is still needed.

Uninstall through Windows Installed apps, remove the macOS app, or remove the
Debian package/AppImage. Preferences and downloaded models remain in the separate
Textify Electron app-data folder unless you explicitly remove that folder.
