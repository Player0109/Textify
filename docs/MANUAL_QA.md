# Textify V1 Manual QA

Run these checks before treating a local archive as a release candidate.

## Bundle Smoke

- Generate the Xcode project from `project.yml`.
- Confirm `xcodebuild -list -project Textify.xcodeproj` shows the `Textify` scheme.
- Build Debug with `xcodebuild` and launch through `./script/build_and_run.sh --full`.
- Archive Release to `dist/archive/Textify.xcarchive`.
- Confirm `dist/` remains untracked.

## V1 Release-Blocking Checks

- Fresh onboarding on a clean machine or account.
- Dictation in TextEdit or Notes, a browser field, and a terminal or code editor.
- Clipboard restoration after insertion.
- Secure field protection.
- Excluded app behavior.
- Clean DMG install and Gatekeeper behavior once DMG packaging exists.
- Sparkle update success and tampered update rejection once Sparkle is added.
- Model download and SHA-256 verification once hosted model assets exist.
- Diagnostics export contains no dictated text.
- Launch at Login behavior, including `.requiresApproval` when macOS requires approval.
