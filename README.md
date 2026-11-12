# Claim Tracker --- AI Agent Implementation Package

This package is for building **Claim Tracker**, an Android-first,
offline personal claims-management app.

## Package contents

-   `MASTER_PROJECT_SPEC.md` --- authoritative product, technical, UX,
    security, and acceptance specification.
-   `PROMPT_1_INITIALIZE.md` --- inspect the environment and establish
    the project foundation.
-   `PROMPT_2_CORE_UI_AND_CLAIMS.md` --- dashboard, claims list, CRUD,
    search, and details.
-   `PROMPT_3_STATUSES_AND_REMINDERS.md` --- status workflow, history,
    and local notifications.
-   `PROMPT_4_ATTACHMENTS_SECURITY_BACKUP.md` --- attachments,
    privacy/security, and encrypted backup/restore.
-   `PROMPT_5_FINAL_QA_AND_APK.md` --- final verification, fixes, and
    APK build.

## How to use

1.  Give the agent `MASTER_PROJECT_SPEC.md` first, or place it in the
    project root.
2.  Start with Prompt 1.
3.  Do not skip phases. Give the next prompt only after the previous
    phase has passed its checks.
4.  Keep the spec and progress files in the project repository.
5.  If the agent session ends, resume by asking it to read
    `MASTER_PROJECT_SPEC.md`, `IMPLEMENTATION_PROGRESS.md`, and
    `WORK_LOG.md` before continuing.

## Important boundaries

-   Android (APK) and iOS (unsigned IPA built by GitHub Actions; see
    "iOS build" below). iOS was added by owner decision on 2026-11-12.
-   Single user, local-only storage. No backend, account system, cloud
    sync, analytics, or telemetry.
-   Per-claim custom reminders.
-   No contact/call communication log.
-   Arabic-first RTL interface.
-   Design system: Premium Modern, Light + Dark themes, Balanced claim
    cards.
-   The agent must not claim that a test or build succeeded unless it
    actually ran and verified it.

## Security and backup design (Phase 4)

This section is the required handoff documentation for the encryption, key
handling, and backup format decisions (spec §15, prompt 4 "Handoff"). It is an
engineering description — **not** a security certification or legal-compliance
claim.

### Encryption (`lib/core/security/backup_crypto.dart`)

-   Key derivation: PBKDF2-HMAC-SHA256 with a random 16-byte salt and
    100,000 iterations (via the `crypto` package). The 64-byte output is split
    into an AES key (first 32 bytes) and a separate HMAC key (last 32 bytes).
-   Cipher: AES-256 in CTR mode with a random 16-byte IV, implemented on top of
    `pointycastle`'s well-reviewed primitives.
-   Integrity: encrypt-then-MAC — an HMAC-SHA256 tag over the ciphertext is
    verified with a constant-time comparison before any plaintext is released.
    A wrong passphrase or corrupted archive therefore fails closed and never
    yields partial data.
-   The passphrase is supplied by the user at export/restore time. It is **never
    stored, cached, logged, or transmitted** anywhere in the app (pinned by
    `test/core/security_audit_test.dart`).

### Backup file format v1 (`lib/core/constants/app_constants.dart`)

```
magic "CTBK" (4 bytes) | u16 version=1 | salt (16) | u32 iterations
| u64 payload length N | IV (16) + ciphertext (N-16) | HMAC tag (32)
```

The encrypted payload is a small binary envelope: the SQLite database file
bytes, then every attachment as `u32 relativePathLen ‖ path ‖ u64 bytesLen ‖
bytes`. The version field and magic let restore reject unknown or foreign files
before any mutation (spec §15 "verify integrity and version before restore").

### Staged restore (`lib/core/security/backup_service.dart`)

`restoreFrom` never touches live data until validation succeeds:

1.  Decrypt + MAC-verify the whole archive in memory (wrong passphrase →
    `WrongPassphraseError`, nothing changed).
2.  Parse into a temp staging directory with bounds-checked reads and
    path-traversal rejection (`_validatedRelativePath`).
3.  Validate: `PRAGMA integrity_check` on the staged DB, row counts, and that
    every attachment file exists non-empty.
4.  Only then swap: replace the live DB file and move staged attachments into
    `<documents>/attachments`. The live DB handle is closed during the swap;
    the caller reopens via `AppDatabase.open()` (wired in `lib/main.dart`'s
    `reconnectAfterRestore`).

### Privacy posture (spec §14)

-   No network transmission: the production manifest declares **no** INTERNET
    permission (`test/core/security_audit_test.dart` pins this). The debug/
    profile variants keep the stock Flutter template permission for hot-reload
    tooling only — it is not part of any shipped build.
-   All data (DB, attachments) lives in app-private storage; no telemetry, no
    analytics, no accounts.
-   Notifications use generic text (`AppConstants.genericReminderTitle/Body`)
    so claim details never appear on the lock screen.
-   No hardcoded key material and no sensitive logging — both pinned by the
    audit test above.

### Known limitations (honest handoff)

-   PBKDF2 iteration count is fixed at 100,000; raising it later requires a
    format version bump (the field is in the header for exactly this).
-   CTR mode provides no authenticated encryption by itself — integrity comes
    from the separate HMAC tag (encrypt-then-MAC), which must stay verified.
-   Restore replaces the current local data set; the UI warns before it runs,
    but there is no automatic pre-restore snapshot of the outgoing state.
-   The app does not claim FIPS/CCS or any other certification; the crypto
    choices are standard, well-reviewed primitives used in a documented way.

## Release build and installation (Phase 5)

### Build

```
flutter pub get
flutter test                 # full suite: 123 tests
flutter analyze              # no issues
dart format --set-exit-if-changed lib test   # clean
flutter build apk --release  # -> build\app\outputs\flutter-apk\app-release.apk
```

Verified artifact (2026-11-12): `build\app\outputs\flutter-apk\app-release.apk`,
**57,520,895 bytes (54.9 MB)**, built in ~70 s on Windows 11 with Flutter 3.47.9 /
Dart 3.13.7, AGP 9.5.1, Gradle 9.6.0, compileSdk 37, minSdk 23 (Android 6.0+).

### Signing status (stated honestly)

The release buildType in `android/app/build.gradle.kts` uses the **debug
keystore** (`signingConfig = signingConfigs.getByName("debug")`). The APK is a
validly signed, installable release-mode build — suitable for sideloading and
hand-off. It is **not** Play-distribution ready: uploading to Google Play
requires creating a real keystore and configuring `signingConfigs.release`.

### Install on an Android device (API 23+)

1. Copy `app-release.apk` to the device (USB, email, drive — your choice).
2. On the device: open the file in any file manager, or run
   `adb install -r app-release.apk` from a computer with USB debugging enabled.
3. Allow "Install unknown apps" for the source app if prompted.
4. Launch **Claim Tracker**. First launch asks for notification permission —
   grant it to receive reminders (the app also explains how to enable exact
   alarms on Android 12+ when needed).

Verified on: emulator-5554 (`sdk gphone64 x86_64`, Android 17 / API 37) —
install Success, launched and fully drawn in ~1.3 s, no crash in the app's
process, no personal data in its log lines (see `WORK_LOG.md` Phase 5 entry).

### Known limitations (Phase 5 handoff)

-   **Reminders are one-time only** — per spec §10's fallback clause; recurring
    interval controls were deliberately not built.
-   **Reboot alarm delivery** relies on flutter_local_notifications' boot
    receiver plus the startup reconcile in `lib/main.dart`; launch/crash
    behavior was verified on an emulator, but a full 24 h alarm-fire cycle was
    not exercised.
-   **iOS** has its own limitations; see "iOS build" below.
-   **Debug-keystore signing** as described above; no Play-distribution
    readiness claim is made.
-   Backup/restore replaces the current local data after an explicit warning;
    there is no automatic pre-restore snapshot.

## iOS build (GitHub Actions, unsigned IPA)

A Windows PC cannot build iOS apps, so the IPA is built in the cloud on a
GitHub-hosted Mac by [`.github/workflows/ios-build.yml`](.github/workflows/ios-build.yml).

1.  Push this project to a GitHub repository (branch `main` or `master`).
    The workflow also has a manual **Run workflow** button (Actions tab).
2.  The workflow runs `flutter analyze` + `flutter test` on Linux, then
    `flutter build ios --release --no-codesign` on macOS, and zips
    `Runner.app` into `Payload/` → `ClaimTracker-unsigned.ipa`.
3.  Download it: **Actions → iOS build → latest run → Artifacts →
    ClaimTracker-unsigned-ipa** (a .zip that contains the .ipa; kept 30 days).
4.  The IPA is **unsigned**. Sign/install it with your own tool (AltStore,
    Sideloadly, a signing service, …), which re-signs it with your Apple ID or
    certificate. No Apple secrets are stored in this repository.

Bundle identifier: `com.claimtracker.claimTracker` · minimum iOS 15.0 ·
build number = the workflow run number.

### iOS-specific behavior

-   **Notifications**: permission is requested only after the in-app
    explanation (no prompt at launch). iOS fires calendar-scheduled local
    notifications at their exact time, so the Android exact-alarm and
    battery-optimization rows are hidden in Settings on iOS.
-   **Attachments**: images open in-app as before; PDFs and documents open in
    the system QuickLook viewer (`com.claimtracker/files` channel in
    `ios/Runner/AppDelegate.swift`), because iOS cannot hand a sandboxed file
    to another app through `url_launcher`.

### iOS limitations (stated honestly)

-   The iOS build has **not been run on a Mac or iPhone by the author of this
    change**; the first verification is the GitHub Actions run itself. If it
    fails, the log of the failing step is what needs fixing.
-   iOS keeps at most **64 pending local notifications** per app; reminders
    beyond that are dropped by the OS until the startup reconcile reschedules.
-   A free Apple ID signature (AltStore/Sideloadly) expires after **7 days**
    and must be refreshed; a paid developer certificate lasts longer.
-   Tapping a reminder when the app was fully closed opens the app but does
    not jump to the claim (same as the Android build: no launch-details
    routing).
-   App icon and launch screen are the Flutter defaults (the Android build
    uses the Flutter default icon too).
-   `ITSAppUsesNonExemptEncryption` is set to `false` (backup encryption only
    protects the user's own data on the device). Review this before any
    App Store submission; it does not matter for sideloading.

### Where to read more

-   `MASTER_PROJECT_SPEC.md` — authoritative spec (acceptance criteria in §17,
    definition of done in §20).
-   `IMPLEMENTATION_PROGRESS.md` — phase-by-phase completed work + acceptance
    checklists (all five phases complete as of 2026-11-12).
-   `WORK_LOG.md` — dated technical log: decisions, commands, actual outputs.
