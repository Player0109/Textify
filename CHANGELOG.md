# Changelog

## Unreleased

- Retired the standalone Swift macOS application, its Xcode project, and its
  app-specific tests, build/release scripts, and benchmark runners.
- Retained the desktop application's signed model catalogs, licenses, and
  catalog verification tools and tests.

## [0.2.0 Preview 23] - 2026-09-25

- Published desktop installers for Apple Silicon macOS, Windows x64, and Linux
  x64, with local GPU transcription and separately downloaded speech models.
- Signed and notarized the Mac app and DMG. Windows and Linux installers are
  unsigned; physical-device validation for those platforms and second-Mac
  installation/update checks remain outstanding.
- Added the app logo, setup guide, and working-app demo to the repository README.

[0.2.0 Preview 23]: https://github.com/Player0109/Textify/releases/tag/v0.2.0-preview.23
