# Mac App Store readiness

Assessment: September 26, 2026. The owner requested Mac App Store publication
and confirmed active Apple Developer Program membership and App Store Connect
access. No Store build has been produced, uploaded, or submitted for review.

## Automatic insertion is required

The owner rejected a manual Copy/Paste edition and identified Spokenly as a
Mac App Store example. Preserve hold-to-dictate and automatic insertion. The
initial assessment conflated general Accessibility access with event-posting
permission; its conclusion that sandboxing requires manual paste was too broad.

Apple Developer Technical Support clarified in March 2026 that PostEvent and
ListenEvent privileges work in App Sandbox, while general Accessibility access
for reading/manipulating other apps' UI does not. Both Accessibility and
PostEvent appear in the same System Settings pane. This supports investigating
public Core Graphics event posting for automatic paste without AX permission
as a prerequisite. The same discussion distinguishes technical compatibility
from App Review acceptance; it does not guarantee approval.

Sources: [Apple DTS clarification](https://developer.apple.com/forums/thread/820594),
[Apple sandbox restrictions](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox),
[App Review Guidelines, 2.4.5](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility).

### Implementation to validate

- Use `CGPreflightPostEventAccess` / `CGRequestPostEventAccess` for permission,
  then pasteboard plus a posted Command-V event for insertion.
- Verify the global trigger through Core Graphics event taps and the relevant
  event permission. Avoid AX-gated `NSEvent` global monitoring.
- Separate optional AX target inspection from permission to post events.
  Preserve target identity checks, clipboard restoration and single delivery.
  Establish sandbox-compatible password/secure-input protection before changing
  the existing guard; do not simply delete it to make a test pass.
- Prove the flow in a signed sandbox test using only an owned receiver, then
  integrate it into the Electron MAS build and test the complete dictation flow.

`IsSecureEventInputEnabled` is a useful additional guard, but it is not a
focused-password-field classifier. Apple's [TN2150](https://developer.apple.com/library/archive/technotes/tn2150/_index.html)
describes system handling for native secure fields and explicit opt-in for
custom controls. A false result alone cannot establish that any arbitrary
target is safe. Sandbox parity with the current password-field test remains
unverified.

Spokenly has a [Mac App Store listing](https://apps.apple.com/us/app/spokenly-audio-to-text-ai-app/id6740315592?platform=mac)
and documents automatic insertion. The installed `/Applications/Spokenly.app`
version 2.25.3 has no App Sandbox entitlement or Mac App Store receipt, so its
local signing metadata does not establish the Store build's implementation.
Its exact Store insertion mechanism remains unverified.

### Local prototype checkpoint

An isolated native permission probe is under the ignored
`.spike/mas-input-probe/` directory. It is Developer ID signed with only the
App Sandbox entitlement. Compilation and strict signature verification passed.
Read-only terminal preflight reported sandbox enabled and PostEvent, ListenEvent
and AX trust unavailable. The separately launched probe window subsequently
showed the same state. No permission has been granted and no paste attempted.

The sibling owned receiver is also sandbox-signed and strictly verified. The
probe's explicit test button checks the receiver's exact path, bundle identifier
and PID, preserves clipboard items/types, rechecks target/permission/secure-input
and clipboard ownership, posts one Command-V pair, and restores the clipboard
only if it remains unchanged. The receiver reports PASS only for the exact fixed
public fixture. Actual insertion awaits explicit macOS permission and execution.
This prototype is not an Electron MAS package or a Store build.

## Verified local findings

| Area | Evidence | Work required |
| --- | --- | --- |
| Packaging | `electron/package.json` configures DMG only; `electron/scripts/package.mjs` selects Developer ID signing and notarization. | Add a separate MAS packaging path using Electron's MAS runtime. |
| Entitlements | Neither current Mac entitlement file enables App Sandbox. | Define parent and inherited helper entitlements, microphone, outgoing network, and user-selected read access. |
| Signing | `security find-identity -v` lists Apple Development and Developer ID Application only. | Install the Store application and installer signing identities, with their private keys; obtain matching provisioning profiles. Portal certificates/profiles were not inspected. |
| Automatic insertion | `electron/native/platform-mac.mm:33–44` reads another app's focused element; lines 68–109 require Accessibility trust and post Cmd+V. `electron/src/main/platform.ts:52` selects automatic delivery on macOS. | Replace the AX permission prerequisite with PostEvent checks; validate target and secure-input protection under sandboxing. |
| Global trigger | `electron/src/main/platform.ts:121–175` uses `uiohook-napi`; `electron/src/main/index.ts:243` requires Accessibility. | Retain the trigger and verify its event tap with event-specific permission rather than an AX trust prerequisite. |
| Workers and Metal | `electron/src/main/worker.ts:49` launches bundled executables. | Sign embedded workers with appropriate inheritance and verify actual GPU transcription under the sandbox. Subprocesses are not inherently prohibited. |
| Downloads and import | `electron/src/main/transfer.ts` downloads verified model data; `electron/src/main/index.ts:495` imports user-selected files/folders. | Validate network access, file/folder selection and complete copies into container storage. Explain optional model downloads in review notes. |
| Storage | `electron/src/main/index.ts:35–40` derives storage from Electron's app-data path. | Verify container resolution and define migration; do not assume access to existing direct-download app data. |
| Login and exclusions | `electron/src/main/index.ts:368` configures login startup; the native helper enumerates running apps. | Validate supported login-item behavior and sandbox visibility, then expose only verified capabilities. |

Electron documents separate MAS runtime, sandbox, signing and provisioning
requirements. Developer ID signing serves direct distribution and does not
replace Store signing. The installed `@electron/osx-sign` implementation also
looks for a Mac installer distribution identity when creating a Store package.
See [Electron's submission guide](https://www.electronjs.org/docs/latest/tutorial/mac-app-store-submission-guide).

## Completion criteria

1. Preserve automatic insertion in the Store build and keep the direct-download
   build working. Record any cross-task file handoffs before editing owned files.
2. Build a development-signed MAS app with a matching profile. Verify clean
   launch, microphone permission/capture, model download/import, real Metal
   recognition, automatic insertion, target mismatch rejection, secure-input
   protection, clipboard restoration, restart persistence, cancellation and
   complete worker exit. Inspect sandbox denials. Test the global trigger and
   any supported login item.
3. Produce and validate a Store-signed package. Confirm the registered bundle
   identifier, team, version/build numbers and provisioning profile agree.
4. Prepare the App Store record, accurate screenshots/description, support and
   privacy URLs, privacy answers, age rating, export-compliance answers, price,
   availability and review instructions. Explain the public PostEvent APIs,
   explicit permission and user-triggered insertion. Advertise only tested Store
   behavior. Store updates must use the App Store.
5. Upload through Apple's supported tooling, resolve processing errors, test
   through TestFlight where appropriate, and submit for App Review. Publication
   is complete only after approval and release, not after packaging or upload.

Sources: [Create an app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/),
[Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).

This assessment changes no application behavior, signed catalog, installed app,
credential, or remote release. Existing unrelated working-tree changes remain
outside this task.
