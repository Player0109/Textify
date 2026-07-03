# Textify

Textify is a native macOS menu bar dictation app for quickly turning spoken English into typed text.

V1 is SwiftPM-first and local-first. The first implementation path uses small Swift library targets, mockable boundaries, and a staged `.app` bundle for macOS launch behavior.

## Development

Build and test:

```bash
swift build
swift test
```

Run the menu bar app:

```bash
./script/build_and_run.sh
```

Verify the app bundle launches:

```bash
./script/build_and_run.sh --verify
```
