#!/usr/bin/env bash
set -euo pipefail

swift test
swift build -c release --arch arm64
plutil -lint Resources/Info.plist
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Print :LSUIElement" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" Resources/Info.plist
! rg -n "SUFeedURL|SUPublicEDKey|Sparkle" Resources Sources Package.swift project.yml
! rg -n "Run Mock Dictation|Mock dictation|Developer Mode|Check for Updates|transcript history" Sources/Textify
lipo -archs .build/arm64-apple-macosx/release/Textify | rg '^arm64$'
