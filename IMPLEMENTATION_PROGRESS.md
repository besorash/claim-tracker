# IMPLEMENTATION PROGRESS — Claim Tracker

Source of truth: `MASTER_PROJECT_SPEC.md`. Phase prompts: `PROMPT_1_INITIALIZE.md` … `PROMPT_5_FINAL_QA_AND_APK.md`.

## Current phase

**Phase 5 (Final QA, bug fixes, and release APK) — COMPLETE.**
All five phases are done. The project is ready for handoff.

## Completed work (Phase 1)

- Flutter Android-only project initialized in `c:/Users/Majesty/Projects/finaldev`
  (package id `com.claimtracker.claim_tracker`, app name "Claim Tracker").
- Folder structure per spec §13: `lib/core/{constants,database,l10n,models,notifications,theme,utils}`,
  `lib/app/home_shell.dart`, `lib/shared/widgets/`.
- Database layer (spec §13): SQLite via `sqflite` (+ `sqflite_common_ffi` for host tests),
  schema v1 with six tables (`claims`, `status_history`, `reminders`, `attachments`,
  `insurance_companies`, `app_settings`), FK cascades, indexes, migration path in
  [`lib/core/database/app_database.dart`](lib/core/database/app_database.dart).
- Repositories (no DB access from UI): claims CRUD/search/filters/sort, atomic status-history
  transactions, reminders, attachments metadata, settings.
- Models: `Claim`, `Reminder`, `Attachment`, `InsuranceCompany`, `StatusHistoryEntry`,
  and the ten fixed Arabic statuses in [`lib/core/models/claim_status.dart`](lib/core/models/claim_status.dart).
- Time foundation (spec §2): Asia/Riyadh day boundaries, Arabic date formatting, SAR amounts —
  [`lib/core/utils/time_utils.dart`](lib/core/utils/time_utils.dart).
- Notification foundation (spec §10, Phase 1 scope only): channel creation, permission helpers,
  `zonedSchedule`/cancel/reconcile in [`lib/core/notifications/notification_service.dart`](lib/core/notifications/notification_service.dart);
  startup reconciliation wired in [`lib/main.dart`](lib/main.dart).
- Theme tokens + Light/Dark (spec §3.1–§3.2) and Arabic RTL shell with four honest placeholder
  destinations (no fake controls, per spec §18): [`lib/core/theme/app_theme.dart`](lib/core/theme/app_theme.dart),
  [`lib/app/home_shell.dart`](lib/app/home_shell.dart). Cairo font bundled (`assets/fonts/`).

## Phase 1 acceptance checklist (all verified)

- [x] `flutter doctor -v` — no issues (Flutter 3.47.9, Dart 3.13.7, Android SDK 36 + platform 37, JDK 17).
- [x] Dependency resolution (`pub get`) — clean; versions pinned in `pubspec.lock`.
- [x] Formatter: `dart format lib test` — 24 files, 0 changes (clean).
- [x] Static analysis: `flutter analyze` — **No issues found**.
- [x] Tests: `flutter test` — **All tests passed** (28/28 across schema, repositories, time utils, widget shell).
- [x] Android debug build: `flutter build apk --debug` — **Built successfully**:
  `C:\Users\Majesty\Projects\finaldev\build\app\outputs\flutter-apk\app-debug.apk` (161.94 MB).

## Known issues / decisions to carry forward

- AGP upgraded 9.1.0 → **9.5.1** and Gradle wrapper 9.3.1 → **9.6.0** because
  `flutter_local_notifications` 23.0.1 (and androidx.core 1.19) require compileSdk 37;
  core library desugaring enabled in [`android/app/build.gradle.kts`](android/app/build.gradle.kts).
- `TimeUtils.ensureInitialized()` is now **async** (initializes intl Arabic locale data);
  callers must await it (done in `NotificationService.init` and tests).
- `ClaimsRepository.create()` strips the explicit `id` so new rows get auto-increment ids.

## Completed work (Phase 2)

- **Dashboard** ([`lib/features/dashboard/`](lib/features/dashboard/)): metric tiles + needs-attention list, every number from SQLite (spec §5); compensated stays OPEN.
- **Claims list** ([`lib/features/claims/claims_list_screen.dart`](lib/features/claims/claims_list_screen.dart), [`claim_card.dart`](lib/features/claims/claim_card.dart)): search + filter chips on one code path, balanced cards, overdue indicators (spec §6).
- **Claim form** ([`claim_form_screen.dart`](lib/features/claims/claim_form_screen.dart), [`claim_form_model.dart`](lib/features/claims/claim_form_model.dart)): all four spec §7 sections, Arabic validation with input preservation on failure; self-pops after `onSaved`.
- **Claim details** ([`claim_details_screen.dart`](lib/features/claims/claim_details_screen.dart)): read-only sections + Edit/Delete (spec §11); no Phase 3 stubs.
- **Settings** ([`lib/features/settings/settings_screen.dart`](lib/features/settings/settings_screen.dart)): theme selection persisted in SQLite and live-applied; notifications card read-only (spec §16).
- **Shell wiring** ([`lib/app/home_shell.dart`](lib/app/home_shell.dart), [`lib/main.dart`](lib/main.dart)): four real destinations — Reminders = follow-up-filtered list (honest interim, spec §3.3); FAB add/edit flows; `_gen`/ValueKey remount pattern keeps IndexedStack fresh after mutations.

## Phase 2 acceptance checklist (all verified)

- [x] `flutter analyze` — **No issues found**.
- [x] `dart format lib test --output=write` — clean.
- [x] `flutter test` — **All tests passed, 65/65** (schema ×6, repositories ×9, time utils ×7, dashboard service ×4, dashboard screen ×3, claims list ×4, form model ×8, form screen ×4, details ×5, settings ×4, shell e2e ×4).
- [x] `flutter build apk --debug` — **Built successfully**:
  `C:\Users\Majesty\Projects\finaldev\build\app\outputs\flutter-apk\app-debug.apk` (186.25 MB, 2026-11-11 23:02 local).

## Known issues / decisions to carry forward (Phase 2)

- No Android device/emulator in this environment — APK verified by build only; on-device verification is a Phase 5 item per spec §20.
- Reminders destination is the follow-up-filtered claims list (honest interim); interactive reminder scheduling + status-change flow with atomic history land in **Phase 3** on the existing `NotificationService` and `StatusHistoryRepository`.
- Widget-test harness rules accumulated this phase (FFI I/O only inside one `runAsync`; bounded settle instead of `pumpAndSettle`; nav taps scoped to `NavigationBar`) are recorded in `.superpowers/sdd/2026-11-11-phase2-core-ui-and-claims.md/progress.md` — reuse them for Phase 3 tests.

## Completed work (Phase 3)

- **ReminderScheduler seam** ([`lib/core/notifications/reminder_scheduler.dart`](lib/core/notifications/reminder_scheduler.dart)): abstract injection point for the four OS-side operations; production = `NotificationService implements ReminderScheduler`, widget/orchestration tests inject a recording fake — no method channels on host.
- **ClaimActions orchestration** ([`lib/features/claims/claim_actions.dart`](lib/features/claims/claim_actions.dart)): every multi-table mutation flow in one place — atomic status+history, save/reschedule/disable reminder (stable `notificationId == claimId`), close/delete that cancel the OS alarm first; best-effort cancel so a failing scheduler never aborts the user flow.
- **Status-change dialog** on [`claim_details_screen.dart`](lib/features/claims/claim_details_screen.dart): status dropdown over `ClaimStatus.all`, optional note, explicit follow-up decision (keep / set new date-time / clear) — persist-before-pop ordering.
- **Status history section**: newest-first list with the current-status row visually distinguished (filled chip vs plain label), muted empty state; loaded only while the claim exists.
- **Reminder section + permission flow** (spec §10): enabled/disabled state line, fire-time row, set/reschedule always available, disable rendered only when an enabled reminder exists (§3.3 no non-functional buttons). Permission-aware save: explanation dialog → explicit allow → request; in-app state persists regardless of OS permission; still-denied path shows the Arabic "how to enable" dialog after persistence.
- **Notification-tap routing** ([`lib/app/home_shell.dart`](lib/app/home_shell.dart), [`lib/main.dart`](lib/main.dart)): `HomeShell.openClaimFromNotification` static hook set in `initState`, cleared on dispose (identity-guarded); `main.dart` bridges `NotificationService.onClaimTapped` to it — a reminder tap after cold start opens the right claim; unknown ids land on the not-found state.

## Phase 3 acceptance checklist (all verified)

- [x] `flutter analyze` — **No issues found**.
- [x] `dart format lib test --output=write` — clean.
- [x] `flutter test` — **All tests passed, 79/79** (schema ×6, repositories ×9, time utils ×7, dashboard service ×4, dashboard screen ×3, claims list ×4, form model ×8, form screen ×4, claim actions ×5, details ×12, settings ×4, shell e2e + routing ×6).
- [x] `flutter build apk --debug` — **Built successfully**:
  `C:\Users\Majesty\Projects\finaldev\build\app\outputs\flutter-apk\app-debug.apk` (186.27 MB, 2026-11-12 01:25 local).

## Known issues / decisions to carry forward (Phase 3)

- One-time-only reminders shipped per spec §10's fallback clause — recurring-interval controls deliberately NOT built; `repeatIntervalHours` stays null from the UI.
- Reboot reconciliation and real notification delivery are **not host-testable** (no device/emulator); they rely on flutter_local_notifications' boot receiver + startup reconcile in `main.dart`. Flagged as Phase 5 on-device verification items.
- Widget-test harness rules accumulated this phase (explicit-duration pumps until route animation completes; strong settle signals — absent-until-done state, never text already in the tree; ms-precision seeds for INTEGER-ms columns) are recorded in `.superpowers/sdd/2026-11-11-phase3-statuses-and-reminders.md/progress.md` — reuse them for Phase 4 tests.

## Completed work (Phase 4)

- **Attachment file service** ([`lib/features/attachments/attachment_file_service.dart`](lib/features/attachments/attachment_file_service.dart)): copies picked files into app-private `<documents>/attachments/<subdir>/<name>` with sanitized names, bounds-checked path resolution (`_resolveGuarded`), per-file delete, and `replaceStoreFrom` for restore — no file ever leaves private storage (spec §12).
- **Picker seam** ([`lib/features/attachments/attachment_picker_seam.dart`](lib/features/attachments/attachment_picker_seam.dart)): `AttachmentPicker` abstraction over `file_picker`; production = `FilePickerAttachmentPicker`, tests inject a fake — no method channels on host.
- **ClaimActions.attachFile / delete cleanup** ([`claim_actions.dart`](lib/features/claims/claim_actions.dart)): metadata + physical copy in one flow; claim deletion cancels reminders, removes rows, and best-effort deletes each attachment file (spec §12 "safe deletion/cleanup").
- **Attachments UI on details screen** ([`claim_details_screen.dart`](lib/features/claims/claim_details_screen.dart)): list with human-readable sizes + missing-file flag, add via picker (image/PDF/common), tap-to-open — images in an in-app dialog, other types via `url_launcher` external app; delete with confirm.
- **Backup crypto** ([`lib/core/security/backup_crypto.dart`](lib/core/security/backup_crypto.dart)): PBKDF2-HMAC-SHA256 (random salt, 100k iters) → AES-256 key ‖ HMAC key; AES-256-CTR + encrypt-then-MAC with constant-time tag compare; format v1 header `CTBK‖u16 ver‖salt‖iters‖len‖IV+ct‖tag`. Wrong passphrase / corrupt archive fail closed (spec §15).
- **BackupService** ([`lib/core/security/backup_service.dart`](lib/core/security/backup_service.dart)): `exportTo` writes the encrypted DB+attachments envelope; `restoreFrom` decrypts → validates (integrity_check, row counts, every attachment present non-empty) in a staging dir with traversal rejection → swaps only after success. Never destroys live data before validation passes.
- **Settings backup/restore card** ([`settings_screen.dart`](lib/features/settings/settings_screen.dart)): export to user-chosen file, restore from picked archive with passphrase entry + explicit warning dialog before replace; Arabic error messages for wrong password / corrupt archive / incompatible version (spec §15–§16).
- **Security audit tests** ([`test/core/security_audit_test.dart`](test/core/security_audit_test.dart)): pins spec §14 as executable checks — generic notification text, no INTERNET permission in the production manifest, no sensitive logging in `lib/`, no hardcoded key material.
- **Production wiring** ([`main.dart`](lib/main.dart), [`home_shell.dart`](lib/app/home_shell.dart)): documents dir resolved once at startup → shared `AttachmentFileService(baseDir)` + `BackupService`; post-restore `reconnectAfterRestore` reopens the DB and rebuilds the shell around it (spec §15 "caller reopens through AppDatabase.open()").
- **Handoff docs**: encryption design, key handling, backup format v1, privacy posture, and known limitations recorded in [`README.md`](README.md) — explicitly NOT a security certification or legal-compliance claim.

## Phase 4 acceptance checklist (all verified — final gate passed 2026-11-12)

- [x] `flutter analyze` — **No issues found**.
- [x] `dart format --set-exit-if-changed lib test` — clean (0 changed).
- [x] `flutter test` — **All tests passed, 119/119** (schema ×5, repositories ×12, time utils ×8, dashboard service ×4, dashboard screen ×3, claims list ×4, form model ×12, form screen ×4, claim actions ×5 + attachments ×5, details ×18 incl. attachment UI, settings ×9 theme+backup card, shell e2e + routing ×6, crypto ×7, backup service ×7, file service ×6, security audit ×4).
- [x] Attach+reopen image and PDF paths covered by widget tests (in-app dialog / external-launch seam); persistence across restart covered by the existing e2e harness.
- [x] Export→restore round-trip in a clean state verified by `test/core/backup_service_test.dart` (claims, history, reminders, attachment files all restored; wrong password and corrupt archive leave existing data untouched).
- [x] `flutter build apk --debug` — **Built successfully** (`√ Built build\app\outputs\flutter-apk\app-debug.apk`, Gradle `assembleDebug` in ~46 s).

## Known issues / decisions to carry forward (Phase 4)

- **Test-harness flake root-caused and fixed** (`test/widget_test.dart`): sqflite_common caches open helpers per path — every test file sharing `:memory:` could receive an earlier test's already-migrated connection, so a later `_openInMemory()` threw "table claims already exists" under parallel load. Fixed by opening with `OpenDatabaseOptions(singleInstance: false)` (fresh native DB per call) plus bounded real-time settle loops for the two notification-routing tests. Full suite green twice in a row after the fix; see WORK_LOG 2026-11-12 Task 8 entry.
- PBKDF2 iterations fixed at 100k; raising them later needs a format-version bump (header field exists for this).
- CTR mode is not self-authenticating — integrity relies on the separate HMAC tag (encrypt-then-MAC); keep it verified before any plaintext use.
- Restore replaces current local data after an explicit warning; no automatic pre-restore snapshot of outgoing state.
- Debug/profile manifests keep the stock Flutter INTERNET permission for hot-reload tooling only; production manifest is clean (audit-pinned).
- No device/emulator in this environment — on-device attachment open, notification delivery, and backup file sharing remain Phase 5 verification items per spec §20.

## Completed work (Phase 5)

- **Independent acceptance audit** vs spec §17–§20: every area re-verified from source + fresh test runs rather than trusting phase reports — claims CRUD/search/filters/dashboard counts/persistence, atomic status history, reminder schedule/reschedule/disable/close-cancel/reconcile/tap-routing/permission-denied paths, attachment attach/open/delete cleanup, export→restore round-trip with wrong-passphrase and corrupt-archive fail-closed behavior.
- **Bug 1 (contract violation) — fixed TDD**: `ClaimActions.attachFile` force-unwrapped a nullable base dir (`svc.baseDir!.path`) which could throw on the null-baseDir construction path. Added null-safe [`AttachmentFileService.storedFileFor(relativePath)`](lib/features/attachments/attachment_file_service.dart) (resolves via `storeDir()` + `_resolveGuarded`, same traversal guard as every other accessor); `attachFile` now uses it for size computation. Regression test: [`test/features/attachment_file_service_test.dart`](test/features/attachment_file_service_test.dart).
- **Bug 2 (stale alarms after restore) — fixed TDD**: a restored DB could leave OS-side alarms from the pre-restore dataset pending. Extended the [`ReminderScheduler`](lib/core/notifications/reminder_scheduler.dart) seam with `reconcile(List<Reminder> enabledReminders)`; production implementation in [`NotificationService.reconcile`](lib/core/notifications/notification_service.dart) cancels all pending then reschedules future-enabled reminders; wired into post-restore flow via `ClaimTrackerApp.scheduler` + `reconnectAfterRestore()` in [`main.dart`](lib/main.dart), best-effort (a failing scheduler never breaks the restore). Regression tests: [`test/features/restore_reconcile_test.dart`](test/features/restore_reconcile_test.dart) (3 tests — exact enabled set delivered, disabled excluded, failure isolation); all three existing `FakeScheduler`s updated.
- **Privacy/network audit**: zero logging calls in `lib/` (audit-pinned), zero network package imports (`http`/`dio`/sockets absent from pubspec), production manifest declares no INTERNET permission; `url_launcher` used only for user-initiated external attachment opens (spec §12).
- **Theme/RTL verification**: all screen tests run under `AppTheme.light()` with dark variants; explicit dark-mode test + `'dark'` persistence assertion in settings tests; Arabic RTL shell unchanged.
- **Release APK built and verified on device** — see checklist below.

## Phase 5 acceptance checklist (all verified — final gate passed 2026-11-12)

- [x] `dart format --set-exit-if-changed lib test` — clean ("Formatted 52 files (0 changed)").
- [x] `flutter analyze` — **No issues found!**
- [x] `flutter test` — **All tests passed, 123/123** (baseline 119 + 4 new Phase 5 regression tests; zero regressions from the `ReminderScheduler` interface change).
- [x] Both bugs fixed red→green with failing tests first; full suite re-run green after each fix.
- [x] No sensitive logging, no network dependency, no INTERNET permission in production manifest (audit-pinned + manual re-check this phase).
- [x] Light/Dark themes and Arabic RTL verified across all screen tests.
- [x] `flutter build apk --release` — **√ Built** in ~70 s → `build\app\outputs\flutter-apk\app-release.apk`, **57,520,895 bytes (54.9 MB)**, 2026-11-12 06:56 local (file existence + size verified via `dir`).
- [x] On-device verification — emulator-5554 (`sdk gphone64 x86_64`, Android 17 / API 37): `adb install -r` → **Success**; launched `com.claimtracker.claim_tracker/.MainActivity` → "Displayed +1s341ms", "Fully drawn +1s341ms"; no crash in our process (the FATAL EXCEPTION lines in logcat belong to a different pre-installed app, `com.example.claimstracker`); no personal-data patterns in our log lines.
- [x] Signing status documented: release build signed with the **debug keystore** (`signingConfig = signingConfigs.getByName("debug")` in [`android/app/build.gradle.kts`](android/app/build.gradle.kts)) — local/distribution-by-hand only, NOT Play-distribution ready (no invented credentials, per prompt constraint).
- [x] Handoff docs updated: this file, [`WORK_LOG.md`](WORK_LOG.md) Phase 5 entry with fresh evidence, [`README.md`](README.md) install instructions + known limitations.

## Known issues / decisions to carry forward (Phase 5)

- **Signing**: release APK uses debug keys — fine for sideloading/hand-off; a Play upload requires a real keystore and `signingConfigs.release` configuration (documented, not fabricated).
- One-time-only reminders per spec §10 fallback clause (recurring controls deliberately not built).
- Real notification delivery after device reboot relies on flutter_local_notifications' boot receiver + startup reconcile — launch/crash behavior verified on emulator; a full 24 h alarm-fire cycle was not exercised.
- ~~No iOS build (Android-only scope, spec §2).~~ Superseded 2026-11-12 — see below.

## Post-release: iOS target (2026-11-12, owner decision)

- `ios/` generated with `flutter create --platforms=ios --org com.claimtracker` (bundle id `com.claimtracker.claimTracker`, iOS 15.0, Swift Package Manager plugin integration from the Flutter 3.47.9 template, UIScene lifecycle).
- Notifications made iOS-aware in [`notification_service.dart`](lib/core/notifications/notification_service.dart): Darwin init settings (no launch prompt), iOS permission request/check, foreground presentation, exact-alarm/battery helpers report "nothing to do" on iOS. `AppDelegate.swift` sets the `UNUserNotificationCenter` delegate.
- Settings hides the Android-only exact-alarm and battery rows on iOS ([`settings_screen.dart`](lib/features/settings/settings_screen.dart)); the "notifications denied" text is now platform-neutral (EN/AR ARB + regenerated l10n).
- Non-image attachments open in QuickLook on iOS via the `com.claimtracker/files` channel ([`AppDelegate.swift`](ios/Runner/AppDelegate.swift), [`claim_details_screen.dart`](lib/features/claims/claim_details_screen.dart)); Android path unchanged.
- `Info.plist`: `CFBundleLocalizations` (en, ar), `NSPhotoLibraryUsageDescription`, `ITSAppUsesNonExemptEncryption=false`.
- CI: [`.github/workflows/ios-build.yml`](.github/workflows/ios-build.yml) — analyze + test on Linux, then unsigned `flutter build ios --release --no-codesign` on macOS packaged as `ClaimTracker-unsigned.ipa` (artifact).
- `.gitignore`: device debug dumps under `tools/` (DB copy with claim rows, UI/logcat/alarm dumps) and IPA outputs are excluded from git.
- Fixed a flaky test (`backup_service_test.dart` wrong-passphrase case: un-awaited `expect` + global temp-dir scan raced with parallel test files).

### iOS acceptance checklist

- [x] `flutter analyze` — No issues found.
- [x] `flutter test` — 151/151 passed (3 consecutive full 150/150 runs after the flaky-test fix; final full run 151/151 incl. the new iOS settings test).
- [ ] `flutter build ios` / IPA — **not verifiable on Windows**; first verification is the GitHub Actions run.
- [ ] On-device iOS check (notifications, QuickLook, file picker, backup/restore) — not done.

## Next action

Push to GitHub and let the "iOS build" workflow run; download the `ClaimTracker-unsigned-ipa` artifact, sign/install it with your sideloading tool, and run the on-device checks above. The Android release APK flow is unchanged.
