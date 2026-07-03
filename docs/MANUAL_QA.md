# Textify V1.1 Manual QA

Run these checks before publishing a V1.1 GitHub Release. Any unchecked item is
release-blocking.

## Release-Blocking Checks

- [ ] 1. Fresh install from stapled DMG on macOS 14+ Apple Silicon.
- [ ] 2. Gatekeeper opens app without override.
- [ ] 3. No Dock icon by default.
- [ ] 4. Menu bar icon appears.
- [ ] 5. Onboarding installs and verifies `ggml-small.en-q5_1`.
- [ ] 6. Microphone permission flow works.
- [ ] 7. Accessibility permission flow works.
- [ ] 8. Input Monitoring permission flow works.
- [ ] 9. Right Command trigger test passes.
- [ ] 10. Dictation into TextEdit works.
- [ ] 11. Dictation into Notes or browser text field works.
- [ ] 12. Secure password field blocks insertion.
- [ ] 13. Cancelling during processing does not insert late text.
- [ ] 14. Clipboard is restored after paste when marker remains.
- [ ] 15. Clipboard is not overwritten if changed during paste.
- [ ] 16. Diagnostics export contains no transcript or clipboard content.
- [ ] 17. Launch at Login works if enabled.
- [ ] 18. Sparkle UI/framework is absent.
- [ ] 19. App binary is arm64 only.
- [ ] 20. DMG notarization/stapling validation passes.

## Supporting Commands

```bash
git diff --check
bash script/release/validate_release.sh
```

Use `docs/RELEASING.md` for the archive, model publishing, signing,
notarization, stapling, and GitHub Release flow.

## Local Integration Notes - 2026-07-03

Automated checks run on `master`:

- PASS: `swift test` completed 247 tests with 0 failures.
- PASS: `swift build -c release --arch arm64`.
- PASS: `bash script/release/validate_release.sh`.
- PASS: `./script/build_and_run.sh --verify` launched the staged `.app`; the
  launched `Textify` process was stopped after verification.

Manual checks not run in this integration gate:

- Release-blocking checklist items 1-2 and 20 require a Developer ID signed,
  notarized, stapled DMG from a maintainer machine.
- Release-blocking checklist item 5 requires the published model asset,
  license/provenance sidecars, signed manifest, and manifest signature. The
  GitHub Pages manifest endpoints returned 404 during integration.
- Release-blocking checklist items 6-17 require interactive macOS permissions,
  target apps, real dictation, secure-field checks, cancellation checks,
  clipboard checks, diagnostics export, and Launch at Login verification.
