# WORK LOG — Claim Tracker

Dated technical log: decisions, commands, actual outputs, known issues. Newest entries last.

---

## 2026-11-11 — Phase 1 completion (fixes, verification, build)

### Environment (verified via `flutter doctor -v`)

- Flutter 3.47.9 stable (C:\Users\Majesty\develop\flutter), Dart 3.13.7
- Windows 11 (26H2); Android SDK at C:\Users\Majesty\AppData\Local\Android\sdk — platform android-37, build-tools 36.0.0, licenses accepted
- JDK: Temurin 17.0.21; Chrome present; no issues found

### Resolved dependency versions (from pub cache / pubspec.lock)

| Package | Version | Note |
|---|---|---|
| timezone | 0.10.1 | API is `tz.setLocalLocation(Location)` — NOT `setDefaultLocation` |
| intl | 0.20.3 | DateFormat add-methods use underscores: `.add_Hms()` |
| flutter_local_notifications | 23.0.1 | `initialize({required InitializationSettings settings, ...})` — named-only; requires compileSdk 37 + core library desugaring |
| sqflite_common_ffi | 2.4.7 | `SqfliteDatabaseFactory` is NOT re-exported (use type inference); `inMemoryDatabasePath` reachable only via the aliased import (`as ffi`) |

### Fixes applied this session (all verified against package sources before editing)

1. [`lib/core/utils/time_utils.dart`](lib/core/utils/time_utils.dart)
   - L18: `tz.setDefaultLocation(...)` → `tz.setLocalLocation(tz.getLocation(AppConstants.timeZoneId))` (timezone 0.10.1 API).
   - L54: `.addHms()` → `.add_Hms()` (intl 0.20.3 API).
   - **Behavior fix:** `ensureInitialized()` is now `Future<void>` and awaits
     `initializeDateFormatting('ar')` from `package:intl/date_symbol_data_local.dart`.
     Root cause: constructing `DateFormat.yMd('ar')` threw `LocaleDataException` at runtime
     (Arabic locale data not initialized). Callers updated to await it.
2. [`lib/core/models/claim_status.dart`](lib/core/models/claim_status.dart) L100:
   `static const ClaimStatusMeta closed = all.last;` → `static final ...` (`.last` is not a valid const expression).
3. [`lib/core/notifications/notification_service.dart`](lib/core/notifications/notification_service.dart):
   `_plugin.initialize(settings, onDidReceiveNotificationResponse: ...)` → named param
   `settings: settings` (FLN 23 signature); `TimeUtils.ensureInitialized()` now awaited.
4. [`lib/core/theme/app_theme.dart`](lib/core/theme/app_theme.dart):
   removed invalid `side:` parameter from `CardThemeData(...)` — moved the border into the
   `RoundedRectangleBorder(side: ...)`; removed unused local `mutedText` (static helper `AppTheme.muted(context)` already exists).
5. [`lib/core/database/claims_repository.dart`](lib/core/database/claims_repository.dart):
   - Removed unused import `../models/status_history_entry.dart`.
   - **Bug fix in `create()`:** the row map now strips `'id'` before insert
     (`Map.of(claim.toRow())..remove('id')`). Root cause: callers pass `id: 0` as "unsaved";
     inserting an explicit PK caused `UNIQUE constraint failed: claims.id` on the second insert.
6. [`lib/core/database/app_database.dart`](lib/core/database/app_database.dart) L28: string concatenation → interpolation (lint).

### Test fixes

- [`test/database/schema_test.dart`](test/database/schema_test.dart):
  - `openInMemory()`: dropped unexported type annotation (`final factory = ffi.databaseFactoryFfi;`),
    prefixed `ffi.inMemoryDatabasePath`.
  - FK/cascade test: added explicit `PRAGMA foreign_keys = ON` before asserting — the pragma is
    per-connection and cannot be persisted by migration (matches how `AppDatabase.open()` sets it in `onConfigure`).
  - Relative import → `package:claim_tracker/...`.
- [`test/database/repositories_test.dart`](test/database/repositories_test.dart):
  - `setUp`: added `await` on `openDatabase`, prefixed `ffi.inMemoryDatabasePath`, and enabled
    `PRAGMA foreign_keys = ON` so cascade tests match on-device behavior.
  - L76: `final Claim? stored = (await db.claimById(id))!;` → non-nullable `final Claim stored`.
  - Relative imports → `package:` imports.
- [`test/core/time_utils_test.dart`](test/core/time_utils_test.dart):
  - `setUpAll(TimeUtils.ensureInitialized)` → `setUpAll(() => TimeUtils.ensureInitialized())` (now async).
  - Removed unnecessary string interpolation in a matcher reason; relative imports → `package:`.
- [`test/widget_test.dart`](test/widget_test.dart):
  - Scoped finders: each nav label is now asserted inside `find.byType(NavigationBar)`, and the page
    title inside `find.byType(IndexedStack)` — previously `find.text('لوحة التحكم')` matched both the
    bottom-nav label and the placeholder page title (2 widgets → failure).

### Commands executed and actual results

| Command | Result |
|---|---|
| `flutter analyze` | **No issues found** (ran in ~2s) — after fixes; previously 13 errors / 2 warnings / 14 infos |
| `dart format lib test --output=write` | Formatted 24 files, 0 changed (clean) |
| `flutter test` | **All tests passed** — 28/28 (schema v1 ×6, repositories ×9, time utils/status registry ×7, widget shell ×3 + others) |
| `flutter build apk --debug` (attempt 1) | FAILED: FLN 23.0.1 requires compileSdk 37; AGP 9.1.0 max is 36; desugaring missing |
| `flutter build apk --debug` (attempt 2, after AGP bump only) | FAILED: AGP 9.5.1 needs Gradle ≥ 9.6.0 (had 9.3.1) |
| `flutter build apk --debug` (attempt 3) | **√ Built** in ~117s → `build\app\outputs\flutter-apk\app-debug.apk` |

### Build configuration decisions

- [`android/settings.gradle.kts`](android/settings.gradle.kts): AGP `9.1.0` → `9.5.1` (already present in local Gradle cache; supports compileSdk 37).
- [`android/gradle/wrapper/gradle-wrapper.properties`](android/gradle/wrapper/gradle-wrapper.properties): Gradle `9.3.1-all` → `9.6.0-bin` (cached locally as `gradle-9.6.0-bin`).
- [`android/app/build.gradle.kts`](android/app/build.gradle.kts):
  - `compileSdk = maxOf(flutter.compileSdkVersion, 37)`
  - `isCoreLibraryDesugaringEnabled = true` + `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")` (required by FLN 23).

### APK artifact (verified)

- Path: `C:\Users\Majesty\Projects\finaldev\build\app\outputs\flutter-apk\app-debug.apk`
- Size: **161.94 MB** (debug build, all ABIs) — timestamp 2026-11-11 19:48 local.

### Known issues / notes for Phase 2+

- No Android device/emulator connected in this environment; APK verified by successful build only
  (no on-device run). Device verification is a Phase 5 item per spec §20.
- `flutter_local_notifications` emits one deprecation note during compile — harmless, from the plugin itself.
- Release signing still uses debug keys (`android/app/build.gradle.kts` release block) until Phase 5.

### Exact next step

Start **Phase 2**: read [`PROMPT_2_CORE_UI_AND_CLAIMS.md`](PROMPT_2_CORE_UI_AND_CLAIMS.md), then build
dashboard, claims list/search/filters and claim create/edit screens on the existing repositories,
extending tests as features land.

---

## 2026-11-11 (later) — Phase 1 re-execution / verification pass

User requested execution of `PROMPT_1_INITIALIZE.md`. Audited every requirement against the repo and
re-ran the full verification suite for fresh evidence:

| Check | Command | Result |
|---|---|---|
| Environment | `flutter doctor -v` (earlier today) | No issues — Flutter 3.47.9, Dart 3.13.7, SDK platform 37 + build-tools 36, JDK 17 |
| Dependency resolution | `flutter pub get` | **Got dependencies!** (clean; 10 newer versions exist but are incompatible with constraints — expected) |
| Formatter | `dart format lib test --output=write` | 24 files, 0 changed |
| Static analysis | `flutter analyze` | **No issues found** |
| Tests | `flutter test` | **All tests passed — 28/28** |
| Android debug build | `flutter build apk --debug` | **√ Built** (incremental, ~3s) → `build\app\outputs\flutter-apk\app-debug.apk`, 161.94 MB, 2026-11-11 19:52 local |

Requirement audit vs PROMPT_1:
- [x] Tooling inspected and versions reported (above)
- [x] Android-only project in the intended directory; no iOS/web/desktop targets configured
- [x] Dependencies selected & documented: `sqflite` (+`sqflite_common_ffi` for host tests),
      `flutter_local_notifications` 23.0.1, `file_picker`, `flutter_secure_storage`, `crypto`/`pointycastle` (backup encryption, Phase 4) — all in [`pubspec.yaml`](pubspec.yaml)
- [x] Folder structure per spec §13; DB layer + schema v1 + migrations ([`lib/core/database/app_database.dart`](lib/core/database/app_database.dart))
- [x] Theme tokens + Arabic RTL foundation (no full screens yet — placeholders only, per boundary rules)
- [x] Centralized status constants ([`lib/core/models/claim_status.dart`](lib/core/models/claim_status.dart)); DB access kept out of UI widgets
- [x] Arabic locale + forced RTL as default in [`lib/main.dart:87-101`](lib/main.dart)
- [x] Neutral package id `com.claimtracker.claim_tracker` documented (this log, 2026-11-11 entry)
- [x] README, IMPLEMENTATION_PROGRESS.md, WORK_LOG.md present in project root

No new issues found; no code changes required by this pass. Phase 1 remains COMPLETE and ready for Phase 2.

---

## 2026-11-11 (later) — Phase 2 completion (core UI, dashboard, claims)

Executed `PROMPT_2_CORE_UI_AND_CLAIMS.md` natively in-session (user-approved; no git repo → ledger at
`.superpowers/sdd/2026-11-11-phase2-core-ui-and-claims.md/progress.md`, rulings included). TDD per task: RED → verify fail → GREEN → verify pass.

### What was built (all on the Phase 1 repositories — no new dependencies)

- **Dashboard** ([`lib/features/dashboard/dashboard_screen.dart`](lib/features/dashboard/dashboard_screen.dart),
  [`dashboard_service.dart`](lib/features/dashboard/dashboard_service.dart)): metric tiles + needs-attention list, every number from SQLite; compensated stays OPEN per spec §5.
- **Claims list** ([`claims_list_screen.dart`](lib/features/claims/claims_list_screen.dart),
  [`claim_card.dart`](lib/features/claims/claim_card.dart), [`claims_filter.dart`](lib/features/claims/claims_filter.dart)): search + filter chips composing on one code path, balanced cards, overdue indicators.
- **Claim form** ([`claim_form_screen.dart`](lib/features/claims/claim_form_screen.dart),
  [`claim_form_model.dart`](lib/features/claims/claim_form_model.dart)): all four spec §7 sections, Arabic validation with input preservation on failure; form self-pops after `onSaved`.
- **Claim details** ([`claim_details_screen.dart`](lib/features/claims/claim_details_screen.dart)): read-only sections + Edit/Delete (no Phase 3 stubs).
- **Settings** ([`settings_screen.dart`](lib/features/settings/settings_screen.dart)): theme selection persisted in SQLite, live-applied; notifications card read-only.
- **Shell wiring** ([`home_shell.dart`](lib/app/home_shell.dart), [`main.dart`](lib/main.dart)): four real destinations (Reminders = follow-up-filtered list — honest interim per spec §3.3), FAB add/edit flows, theme callback from settings, `_gen`/ValueKey remount pattern for IndexedStack freshness.

### Verification gate (all fresh evidence, 2026-11-11 ~23:02 local)

| Check | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | **No issues found** |
| Formatter | `dart format lib test --output=write` | 40 files, clean after write |
| Tests (full suite) | `flutter test` | **All tests passed — 65/65** (schema ×6, repositories ×9, time utils ×7, dashboard service ×4, dashboard screen ×3, claims list ×4, form model ×8, form screen ×4, details ×5, settings ×4, shell e2e ×4) |
| Android debug build | `flutter build apk --debug` | **√ Built** (~18s incremental) → `build\app\outputs\flutter-apk\app-debug.apk`, **186.25 MB**, 2026-11-11 23:02 local |

### Notable fixes this phase (full rulings in the SDD ledger)

- e2e date-row tap missed for 3 runs: bare `pump()` never elapses the test clock, so route transitions + post-drag inertial scroll stayed mid-motion. Fixed with a bounded fixed-frame settle (`_settle`, ≤60 × [delay 5ms + pump 16ms]) — drains animations like `pumpAndSettle` but can't hang on an indeterminate spinner.
- `dashboard_service_test.dart` "due today" seed was time-of-day flaky (`now + 2h` crosses the Riyadh midnight after ~22:00); now seeds the real day boundary via `TimeUtils.riyadhDayRange(now).$2`.
- sqflite_common_ffi 2.4.7 API split documented in ledger: factory method takes only an options object; named params live on the global wrapper; `sqfliteFfiInit()` does NOT set the global factory (must assign `ffi.databaseFactory = ffi.databaseFactoryFfi;`).

### Known issues / notes for Phase 3+

- No Android device/emulator in this environment — APK verified by build only (device verification is a Phase 5 item per spec §20).
- Reminders destination is the follow-up-filtered claims list (honest interim); interactive reminder scheduling + status-change flow with atomic history land in **Phase 3** on the existing `NotificationService` and `StatusHistoryRepository`.

### Exact next step

Start **Phase 3**: read [`PROMPT_3_STATUSES_AND_REMINDERS.md`](PROMPT_3_STATUSES_AND_REMINDERS.md), then implement the status-change flow (atomic claim + history transaction via the existing `StatusHistoryRepository`) and reminder scheduling on the existing `NotificationService` — extend tests as features land.

---

## 2026-11-12 (early) — Phase 3 completion (statuses, history, reminders, routing)

Executed `PROMPT_3_STATUSES_AND_REMINDERS.md` natively in-session (user-approved; no git repo → ledger at
`.superpowers/sdd/2026-11-11-phase3-statuses-and-reminders.md/progress.md`, rulings included). TDD per task: RED → verify fail → GREEN → verify pass.

### What was built (all on the Phase 1–2 foundation — no new dependencies)

- **ReminderScheduler seam** ([`lib/core/notifications/reminder_scheduler.dart`](lib/core/notifications/reminder_scheduler.dart)): abstract injection point; `NotificationService implements ReminderScheduler`; tests inject a recording fake so no method channels are touched on host.
- **ClaimActions orchestration** ([`lib/features/claims/claim_actions.dart`](lib/features/claims/claim_actions.dart)): atomic status+history, save/reschedule/disable reminder (stable `notificationId == claimId`, replace semantics), close/delete cancel the OS alarm first; best-effort `_safeCancel`; `saveReminder(schedule: bool)` flag for persist-without-schedule on the permission-denied path.
- **Status-change dialog** ([`claim_details_screen.dart`](lib/features/claims/claim_details_screen.dart)): dropdown over `ClaimStatus.all`, optional note, keep/set/clear follow-up decision; persist-before-pop ordering (dialog stays open if the write fails).
- **Status history section**: newest-first, current-status row as filled chip vs plain label for older rows, muted empty state.
- **Reminder section + permission flow** (spec §10): enabled/disabled state line + fire-time row; set always available, disable only when an enabled reminder exists (§3.3); explanation dialog → explicit allow → request; in-app state persists regardless of OS permission; still-denied path shows the Arabic "how to enable" dialog after persistence.
- **Notification-tap routing** ([`lib/app/home_shell.dart`](lib/app/home_shell.dart), [`lib/main.dart`](lib/main.dart)): `HomeShell.openClaimFromNotification` static hook (set in `initState`, identity-guarded clear on dispose); `main.dart` bridges `NotificationService.onClaimTapped → HomeShell.openClaimFromNotification?.call(claimId)`; unknown ids land on the not-found state.

### Verification gate (all fresh evidence, 2026-11-12 ~01:25 local)

| Check | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | **No issues found** |
| Formatter | `dart format lib test --output=write` | 43 files, clean after write |
| Tests (full suite) | `flutter test` | **All tests passed — 79/79** (schema ×6, repositories ×9, time utils ×7, dashboard service ×4, dashboard screen ×3, claims list ×4, form model ×8, form screen ×4, claim actions ×5, details ×12, settings ×4, shell e2e + routing ×6) |
| Android debug build | `flutter build apk --debug` | **√ Built** (~12s incremental) → `build\app\outputs\flutter-apk\app-debug.apk`, **186.27 MB**, 2026-11-12 01:25 local |

### Notable fixes this phase (full rulings in the SDD ledger)

- Reminder section sat below the 600px test viewport (button center y≈871) so `tester.tap` missed with "outside the bounds of the root". Fixed with a `scrollToReminder()` helper — small bidirectional drags until the button's center is within [48, 552] (`scrollUntilVisible` can't work: content renders eagerly).
- Reschedule test settled on text already visible after the first save → second settle exited immediately and raced the persist chain. Fixed by settling on the strong non-UI signal `fake.scheduled.length == N`.
- Carried Phase 2 lessons (explicit-duration pumps until route animation completes; ms-precision seeds for INTEGER-ms columns) — both re-applied here without regression.

### Known issues / notes for Phase 4+

- No Android device/emulator in this environment — APK verified by build only. **Reboot reconciliation and real notification delivery were NOT tested on host**; they rely on flutter_local_notifications' boot receiver + the startup reconcile in `main.dart`. Both flagged as Phase 5 on-device verification items per spec §20.
- One-time-only reminders shipped (spec §10 fallback clause); recurring-interval controls deliberately not built — `repeatIntervalHours` stays null from the UI, repeat strings remain unused rather than stubbed.

### Exact next step

Start **Phase 4**: read [`PROMPT_4_ATTACHMENTS_SECURITY_BACKUP.md`](PROMPT_4_ATTACHMENTS_SECURITY_BACKUP.md), then implement attachments in private storage, encrypted backup/restore, and privacy controls per spec §12–§15 — extend tests as features land.

---

## 2026-11-12 (late) — Phase 4: Tasks 1–2 complete (backup crypto core + BackupService export/staged restore)

Executed `PROMPT_4_ATTACHMENTS_SECURITY_BACKUP.md` per the plan at
[`docs/superpowers/plans/2026-11-11-phase4-attachments-security-backup.md`](docs/superpowers/plans/2026-11-11-phase4-attachments-security-backup.md)
(ledger: `.superpowers/sdd/2026-11-11-phase4-attachments-security-backup.md/progress.md`). TDD per task: RED → verify fail → GREEN → verify pass.

### Task 1 — BackupCrypto core ([`lib/core/security/backup_crypto.dart`](lib/core/security/backup_crypto.dart))

Documented design (spec §15, no compliance claims):
- **KDF**: PBKDF2-HMAC-SHA256, random 16-byte salt per archive, 100,000 iterations, 64-byte output split into AES key ‖ HMAC key.
- **Cipher**: AES-256-CTR (random 16-byte IV; stream mode — no padding). `AESEngine` from pointycastle 4.0.0 — deliberately NOT the deprecated `AESFastEngine` (side-channel issues, flagged by analyzer).
- **Integrity**: encrypt-then-MAC `HMAC-SHA256(macKey, header‖ciphertext)`; tag verified with a constant-time compare BEFORE decryption → wrong passphrase and corruption both fail closed.
- **Format v1** (big-endian): magic "CTBK" ‖ u16 version ‖ salt(16) ‖ u32 iterations ‖ u64 ciphertext-region length N ‖ IV(16)+ciphertext(N−16) ‖ HMAC tag(32).
- No Flutter imports; passphrase never logged or persisted (spec §14).

Rulings: `ByteData.sublistView` requires 8-byte alignment — unaligned header fields use explicit big-endian byte helpers (`_getU16/_getU32/_getU64`). KDF cross-checked in tests against an inline reference PBKDF2 loop.

### Task 2 — BackupService ([`lib/core/security/backup_service.dart`](lib/core/security/backup_service.dart))

- **Export**: reads the live DB file bytes (sqflite is always on-disk) + every attachment row's file; serializes payload `u64 dbLen‖db ‖ u32 count ‖ per-file: name/path/mime (u32-len UTF-8) + u64 dataLen‖bytes`; encrypts via Task 1. A stored row with a missing/empty live file is serialized as zero-length so the archive stays structurally complete — restore then rejects it during staged validation (spec §15 "missing attachments" fails closed on both ends).
- **Restore order** (validate before any mutation of live data):
  1. `formatVersionOf` → decrypt/MAC verify — failures throw BEFORE any filesystem change;
  2. parse payload into a fresh staging dir (`ct_restore*` in system temp) with bounds-checked reads and path-traversal validation on every relative path;
  3. open staged DB read-only: `PRAGMA integrity_check == 'ok'`, count claims, verify every attachment row has a non-empty staged file — else delete staging + throw `CorruptArchiveError`;
  4. swap (only after all of the above): close live DB → replace its file with the staged one → `AttachmentFileService.replaceStoreFrom(staged files)`; caller reopens via `AppDatabase.open()`.
- Every path cleans up staging in `try/finally` — no leftovers on success or failure.

Supporting changes:
- [`AttachmentsRepository`](lib/core/database/attachments_repository.dart): added `listAll()`; fixed latent bug where `create()` inserted an explicit `id` (UNIQUE collision on the second row) — now strips `id` like `ClaimsRepository.create`.
- New [`AttachmentFileService`](lib/features/attachments/attachment_file_service.dart) (Task 3 contract, full behavior next task): store under `<documents>/attachments`, `importFile` copies into a unique subdir and returns the relative path, `fileFor`/`deleteFile` canonicalize + refuse traversal (`..`/`.` segments, absolute paths), `replaceStoreFrom` swaps store contents.

### Verification gate (fresh evidence, 2026-11-12 ~02:35 local)

| Check | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | **No issues found** |
| Formatter | `dart format --set-exit-if-changed lib test` (this SDK has no `flutter format`) | clean (0 changed on re-run) |
| Tests (full suite) | `flutter test` | **All tests passed — 93/93** (was 86 before Phase 4; +7 backup_service, incl. wrong-passphrase / flipped-byte / bad-version / missing-file fail-closed cases and atomic-swap case) |

### Notable fixes this phase

- `sqfliteFfiInit()` only loads the Windows SQLite DLL — it does NOT set the global factory. Host tests that open DBs through the plain sqflite API (BackupService's staged-DB validation) need `sqflite.databaseFactory = ffi.databaseFactoryFfi` in `setUpAll`.
- `Directory.listSync(recursive: true)` is a lazy iterator — deleting entries while iterating it throws (`PathNotFoundException`) once a parent dir is gone. Materialize with `.toList()` first and guard each delete with `existsSync()`.
- Windows path prefix matching must normalize BOTH sides to `/` before comparing (backslash vs slash mismatch produced invalid joined paths).

### Exact next step

Task 3: full `AttachmentFileService` behavior tests (`test/features/attachment_file_service_test.dart`) — import/copy, traversal refusal on delete leaving foreign files intact, safe delete, `replaceStoreFrom`; then Task 4 (attach flow + claim-delete cleanup in `ClaimActions`).

---

## 2026-11-12 (late) — Phase 4: Task 3 complete (AttachmentFileService private store + safe cleanup)

### What was built ([`lib/features/attachments/attachment_file_service.dart`](lib/features/attachments/attachment_file_service.dart))

Final interface per plan Task 3 (Task 2 already codes against it): `const AttachmentFileService({this.baseDir})`, `storeDir()` (`baseDir ?? <documents>/attachments`, created on demand), `importFile(sourcePath, {originalName}) → relative path`, `fileFor(Attachment)`, `isInsideStore(String absolutePath)` (pure check, never throws), `deleteFile(Attachment)`, `replaceStoreFrom(Directory source)`.

- **Import**: copies the picker's file into a unique `<epoch-ms>-<counter>` subdir under the store; hostile names (`../../evil.png`) are sanitized to a flat name — the stored relative path can never contain traversal segments. Source left untouched (picker temp copy cleaned independently).
- **Guard** (`_resolveGuarded`): every disk-touching accessor rejects absolute paths and any `..`/`.` segment with `ArgumentError` before touching disk (spec §12: "avoiding accidental deletion of unrelated files"). `isInsideStore` is the pure predicate form for tests/UI.
- **Delete**: guarded, tolerates already-missing files; a traversal row throws instead of deleting a foreign file.
- **replaceStoreFrom** (restore swap): materializes the recursive listing first (lazy iterator + delete = crash), removes old contents, moves staged files in preserving layout; rename with copy fallback for cross-device.

### Verification gate (fresh evidence)

| Check | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | **No issues found** |
| Formatter | `dart format --set-exit-if-changed` on touched files | clean (0 changed) |
| Tests (full suite) | `flutter test` | **All tests passed — 99/99** (+6 new: import bytes+relative path, hostile-name sanitization, traversal delete refusal with foreign file intact, exact-file delete, store-only resolution, replaceStoreFrom swap without leaks) |

### Exact next step

Task 4: `ClaimActions.attachFile` + claim-delete cleanup (picker seam `attachment_picker_seam.dart`, tests in `test/features/claim_actions_attachments_test.dart`).

---

## 2026-11-12 (late) — Phase 4: Task 4 complete (attach flow + claim-delete cleanup in ClaimActions)

### What was built

- [`lib/features/attachments/attachment_picker_seam.dart`](lib/features/attachments/attachment_picker_seam.dart) (new): `abstract class AttachmentPicker { Future<List<PlatformFile>> pick({required FileType type}); }` + production `FilePickerAttachmentPicker` wrapping file_picker. **API ruling:** file_picker 13.3.3 exposes a *static* API — `FilePicker.pickFiles(type: ...)`; there is no `.platform` getter and no `withData` parameter (both appear in the plan text / older docs). Verified against the pub-cache source of 13.3.3 before writing the seam.
- [`lib/features/claims/claim_actions.dart`](lib/features/claims/claim_actions.dart) (modified):
  - Constructor gains an optional named `files` param: `const ClaimActions(this._db, this.scheduler, {this.files})` — default null keeps every existing positional construction valid (tests + the one production call site in claim_details_screen.dart).
  - New `attachFile(int claimId, String sourcePath, {originalName = '', mimeType = ''})`: copy into store via `AttachmentFileService.importFile` → insert row via `AttachmentsRepository.create` → return the stored `Attachment`. On any DB failure the copied file is deleted (no orphans) and the original error rethrown. Missing source path throws `ArgumentError` before anything is written; no service injected → `StateError`.
  - `deleteClaim` extended: after cancelling/removing reminders, best-effort per-file cleanup of that claim's attachments (`_safeDeleteAttachment`, mirrors `_safeCancel`) **before** `_claims.delete(claimId)` — one failing file never blocks the rest or the row. Skipped entirely when constructed without a service (existing tests keep passing).
- [`test/features/claim_actions_attachments_test.dart`](test/features/claim_actions_attachments_test.dart) (new, 5 tests): attach stores bytes + linked row and returns it; FK-violation insert failure leaves **zero** files in the store; `deleteClaim` removes only that claim's file while B's file stays byte-identical with its row intact (**Review Focus #4**); missing source → typed `ArgumentError`, no partial state; null-service contract (`attachFile` throws, `deleteClaim` still works).

### Verification gate (fresh evidence)

| Check | Command | Result |
|---|---|---|
| RED first | `flutter test test/features/claim_actions_attachments_test.dart` | FAIL as expected — `attachFile` undefined / no `files` param |
| Static analysis | `flutter analyze` | **No issues found** |
| Formatter | `dart format --set-exit-if-changed` on touched files | clean (0 changed on re-run) |
| Tests (full suite) | `flutter test` | **All tests passed — 104/104** (+5 new; was 99 after Task 3) |

### Notable fixes this phase

- file_picker 13.x API drift: plan text says `FilePicker.platform.pickFiles(type:, withData: false)` — neither exists in 13.3.3 (static class, no `withData`). Seam calls `FilePicker.pickFiles(type: type)`.
- `prefer_iterable_wheretype` lint on test leftovers checks → `whereType<File>()`.

### Exact next step

Task 5: Attachments UI on claim details — section `S.attachmentsLabel`, add button `Key('attach-add')`, per-row delete `Key('attach-del-$id')`, tap-to-open (image preview in-app, PDF via url_launcher), new Arabic strings; widget tests extend `test/features/claim_details_screen_test.dart`.

---

## 2026-11-12 (late) — Phase 4: Task 5 complete (attachments UI on claim details)

### What was built

- [`lib/features/claims/claim_details_screen.dart`](lib/features/claims/claim_details_screen.dart) (modified):
  - Constructor gains three optional seams: `picker` (`AttachmentPicker?`, defaults to `FilePickerAttachmentPicker`), `files` (`AttachmentFileService?`), `openExternal` (`Future<bool> Function(Uri)?`, defaults to url_launcher). All existing call sites stay valid.
  - New state: `_attachments` + `_missingPaths`; `_load()` now also loads attachments and (only when non-empty) resolves the store lazily via new `_ensureFiles()` — injected service wins, else a cached instance resolved from `storeDir()`. Attachment-less claims never touch path_provider, so host widget tests stay method-channel-free.
  - New section after status history: empty state (`S.attachmentsEmpty`) or per-row list (name + human size via new `_humanSize`, red `S.attachmentMissing` flag when the physical file is gone) with a tap-to-open `InkWell` and an `IconButton` keyed `Key('attach-del-${a.id}')`; `FilledButton.icon` keyed `Key('attach-add')` in both states.
  - `_addAttachment()`: picker → per-file `ClaimActions.attachFile` (originalName + MIME from new extension map `_mimeFor`) → refresh; picker failure and store-unavailable each get their own Arabic SnackBar (`S.attachmentPickFailed`, `S.attachmentStoreError`). One bad file never aborts the batch.
  - `_openAttachment(a)`: resolve file, existence check (failure → `S.attachmentOpenFailed`); `image/*` previews in a Dialog with `Image.file(fit: contain)` + close button; everything else goes through `widget.openExternal ?? _launchExternal` (`launchUrl(..., mode: externalApplication)` wrapped so exceptions become `false`).
  - `_deleteAttachment(a)`: confirm dialog (`S.deleteAttachmentTitle/Body`) → best-effort file delete (try/catch) → row delete → refresh.
  - `_delete()` now routes through `ClaimActions.deleteClaim` (reminders cancelled + attachment files cleaned up, spec §12); store resolution is attempted only when the claim has attachments and failures are swallowed so deletion always succeeds. Existing delete tests keep passing because their claims have no attachments (no path_provider call) and all OS calls in `deleteClaim` are best-effort.
- [`lib/core/l10n/app_strings.dart`](lib/core/l10n/app_strings.dart): +2 strings — `attachmentPickFailed`, `attachmentStoreError`.
- [`pubspec.yaml`](pubspec.yaml): `cross_file: ^0.3.5` added to dev_dependencies (was transitive) because the test fake implements the `PlatformFile.xFile` member directly; `flutter pub get` promoted it cleanly, no version change in lockfile.
- [`test/features/claim_details_screen_test.dart`](test/features/claim_details_screen_test.dart) (+6 tests): empty state + add button; add flow (fake picker → real temp source file copied into a temp store, row recorded with size 3 + `image/png`, source untouched); image preview in-app (real 1×1 PNG decoded by `Image.file`); non-image open failure (injected `openExternal: false` → SnackBar, then drained so its exit animation completes under runAsync); delete flow (confirm dialog → row gone + physical file gone); missing-file row (flagged with `S.attachmentMissing`, adding still works alongside it).
  - New fakes: `_FakePlatformFile extends PlatformFile` (all abstract members backed by a real temp file; concrete `extension`/`path` inherited) and `_FakePicker implements AttachmentPicker`.
  - Harness extended with the three new seams; new `scrollTo(tester, target)` helper scrolls the *tapped widget itself* into the safe band (the add button is last in the section — scrolling only to the label left it clipped by the bottom bar).

### Verification gate (fresh evidence)

| Check | Command | Result |
|---|---|---|
| RED first | `flutter test test/features/claim_details_screen_test.dart` | FAIL as expected — `No named parameter with the name 'picker'` (screen lacked the seams); fake compile errors fixed before re-running |
| Static analysis | `flutter analyze` | **No issues found** (after removing one unnecessary `!`) |
| Formatter | `dart format --set-exit-if-changed lib test` | clean (0 changed on re-run) |
| Tests (full suite) | `flutter test` | **All tests passed — 110/110** (+6 new; was 104 after Task 4) |

### Notable fixes this phase

- `PlatformFile` is an `abstract base class` → cannot be `implements`d outside its package. Fix: the fake `extends PlatformFile` and is declared `final`; concrete members (`extension`, `path`) are inherited instead of reimplemented.
- url_launcher 6.x returns `Future<bool>` from `launchUrl` (no `LaunchResult` type) — `_launchExternal` wraps it in try/catch → `false`.
- SnackBar exit animation hangs under `runAsync` with duration-less pumps; the PDF-failure test now drains with explicit-duration pumps until the bar is gone.
- Pre-existing reminder test raced tearDown (`database_closed`) once `_load()` gained a fourth query — added a bounded 1s drain at that test's end so the screen's trailing refresh finishes before `raw.close()`.

### Exact next step

Task 6: Settings — backup/restore card (export to user-chosen file, restore with passphrase + staged validation) and security-info card; production wiring resolves the documents dir async and constructs `AttachmentFileService` with an explicit baseDir.

---

## 2026-11-12 (late) — Phase 4: Task 6 complete (settings backup/restore + security cards)

### What was built

- [`lib/features/settings/settings_screen.dart`](lib/features/settings/settings_screen.dart): new optional seams on `SettingsScreen` — `backupService`, `saveArchive` (`Future<Uri?> Function(Uint8List)`), `pickRestoreSource` (`Future<File?> Function()`), `onDataRestored`. When `backupService == null` the backup card is hidden entirely (no dead buttons, spec §3.3).
  - **Export flow** (`_exportBackup`): passphrase dialog → confirm-passphrase dialog (mismatch blocks with `S.backupPassphraseMismatch`, nothing written) → `BackupService.buildArchive(passphrase)` → OS save-file seam → success/failure line in the card. Passphrase is used in memory only, never persisted or logged (spec §15).
  - **Restore flow** (`_restoreBackup`): pick source file → explicit warning dialog (`S.restoreWarningTitle/Body`, spec §15 "clear warnings before restore replaces current data") → passphrase dialog → `BackupService.restoreFrom` (staged validation already guarantees fail-closed) → on success fires `onDataRestored` + shows restored counts; `WrongPassphraseError` / other `BackupError` map to distinct Arabic failure lines.
  - **Security card** (`Key('security-info')`, title `S.securityInfoTitle`): local-only statement, no network/telemetry, encryption summary (PBKDF2 + AES-256), PDPL confirmation note — per plan Task 6 strings.
  - Production defaults: `_defaultSaveArchive` wraps `FilePicker.saveFile(fileName: 'claim-tracker-backup.ctbk', bytes: ...)` (verified in file_picker 13.3.3 source — the OS dialog writes the bytes where the user chooses; this app never picks a shared/public path itself); `_defaultPickRestoreSource` wraps `FilePicker.pickFile`.
- [`lib/core/security/backup_service.dart`](lib/core/security/backup_service.dart): new public `Future<Uint8List> buildArchive(String passphrase)` — builds the encrypted archive bytes without writing to disk (the OS save dialog owns the write). `exportTo(File, ...)` unchanged.
- [`lib/core/l10n/app_strings.dart`](lib/core/l10n/app_strings.dart): +14 Arabic strings (`backupExportAction`, `backupRestoreAction`, `backupPassphraseTitle/ConfirmTitle/Mismatch`, `backupExportedOk`, `restoreWarningTitle/Body`, `restoredOk` template, `backupFailedWrongPassphrase/Corrupt`, `backupExportFailed`, `backupRestoreFailed`, `securityInfoTitle/Body`).
- [`test/features/settings_screen_test.dart`](test/features/settings_screen_test.dart) (+5 tests in a new group): renders both actions + security card; export flow end-to-end (real FFI DB seeded with 1 claim / status change / reminder / 2 attachment files → archive written by the fake save seam starts with `CTBK` magic); restore flow (warning dialog appears BEFORE passphrase entry, success line shows "1 مطالبة و2 مرفقًا", `onDataRestored` fired); wrong passphrase → failure text AND live DB still readable (`appDb.claimById` non-null — fail-closed proven at the UI level); mismatch blocks export with `saveCalled == false`.
  - Group uses a **file-backed** FFI database (BackupService reads DB bytes from its on-disk path; in-memory has no readable path) and sets `sqf.databaseFactory = ffi.databaseFactoryFfi` so `restoreFrom`'s staged-DB open resolves to the FFI backend.

### Verification gate (fresh evidence)

| Check | Command | Result |
|---|---|---|
| RED first | `flutter test test/features/settings_screen_test.dart` | FAIL as expected — `No named parameter with the name 'backupService'` (+ two test-side compile errors fixed: `Claim` requires `customerInsuranceCompany`/`submittedToInsuranceCompany`/`submissionDateUtcMs`; `claimById` lives on `AppDatabase`, not `ClaimsRepository`) |
| Static analysis | `flutter analyze` | **No issues found** (after converting the `fakeSave` closure to a function declaration — `prefer_function_declarations_over_variables`) |
| Formatter | `dart format --set-exit-if-changed lib test` | clean (0 changed on re-run) |
| Tests (full suite) | `flutter test` | **All tests passed — 115/115** (+5 new; was 110 after Task 5) |

### Notable fixes this phase

- file_picker 13.3.3: `PlatformFile.path` is `String?` (nullable in the platform interface) → `_defaultPickRestoreSource` null-guards before constructing `File`.
- `file_picker.saveFile({required fileName, required bytes})` verified against the pub-cache source — export hands finished archive bytes to the OS dialog instead of writing a temp file + sharing it; no shared/public storage path is ever chosen by this app (spec §14).

### Exact next step

Task 7: security hardening pass (`test/core/security_audit_test.dart` — generic notification text, no INTERNET permission in manifest, no sensitive logging, no hardcoded key material) + shell wiring (`home_shell.dart`: construct production `BackupService` with the documents-dir-backed `AttachmentFileService`, pass it plus `onDataRestored: _bump` to `SettingsScreen`; pass real picker/files/openExternal to `ClaimDetailsScreen`) + README backup section.

---

## 2026-11-12 (late) — Phase 4: Task 7 complete (security audit tests + production wiring + handoff docs)

### What was built

- [`test/core/security_audit_test.dart`](test/core/security_audit_test.dart): pins spec §14 as four executable checks —
  1. Notification text in `AppConstants` is generic (no personal data).
  2. The **production** manifest (`android/app/src/main/AndroidManifest.xml`) declares no `android.permission.INTERNET`. Scoped to the main manifest: debug/profile variants keep the stock Flutter template permission for hot-reload tooling only and are not part of shipped builds.
  3. No sensitive logging in `lib/` — regex `\b(print|debugPrint|log)\s*\(` plus a deny-list of sensitive words on the same line.
  4. No hardcoded key material (hex literals ≥32 chars assigned to key/secret/iv/salt identifiers).
- [`lib/app/home_shell.dart`](lib/app/home_shell.dart): new optional ctor params `backupService` (`BackupService?`) + `reconnectAfterRestore` (`Future<void> Function()?`) — passed through to `SettingsScreen` with `onDataRestored: _bump`, so every destination refreshes after a restore (IndexedStack keeps them alive). Null hides the backup card → existing widget tests unchanged.
- [`lib/main.dart`](lib/main.dart): resolves the documents dir once at startup (`getApplicationDocumentsDirectory`) → shared `AttachmentFileService(baseDir: <documents>/attachments)` + `BackupService(db, files)`; `ClaimTrackerApp` now requires `files` + `backup`. State holds mutable live handles and `reconnectAfterRestore()` reopens via `AppDatabase.open()`, then rebuilds the shell around the fresh instance (spec §15 "caller reopens through AppDatabase.open()").
- [`README.md`](README.md): new "Security and backup design (Phase 4)" section — encryption design, key handling, backup format v1 layout, staged restore sequence, privacy posture, known limitations; explicitly NOT a security certification or legal-compliance claim.

### Verification gate (fresh evidence)

| Check | Command | Result |
|---|---|---|
| Audit tests | `flutter test test/core/security_audit_test.dart` | **4/4 passed** (after scoping the INTERNET check to the production main manifest — see fixes below) |
| Static analysis | `flutter analyze` | **No issues found** (after adding the missing `path_provider` import in `main.dart`) |
| Formatter | `dart format --set-exit-if-changed lib test` | clean (0 changed on re-run) |
| Tests (full suite) | `flutter test` | **All tests passed — 119/119** (+4 audit; was 115 after Task 6). One full-suite run showed 2 widget_test.dart failures under parallel FFI load; the file passes alone (6/6) and on re-run — flake, not a regression. |

### Notable fixes this phase

- Dart raw-string gotcha: `r'...[\'"]...'` is invalid — backslashes are literal in raw strings so `'` terminated the string. Fixed with a triple-double-quote raw string `r"""...['"]..."""`.
- INTERNET permission found only in debug/profile manifests (stock Flutter template for hot-reload) → audit scoped to the production main manifest, matching the plan wording exactly; documented in README + progress doc.
- Missing import: `getApplicationDocumentsDirectory` undefined in `main.dart` → added `package:path_provider/path_provider.dart`.

### Exact next step

Task 8: final verification gate per prompt §Verification — full formatter/analyze/test pass plus `flutter build apk --debug`, then finalize IMPLEMENTATION_PROGRESS.md (APK checklist item) and close out Phase 4.

---

## 2026-11-12 (late) — Phase 4: Task 8 complete (final verification gate + APK build; Phase 4 closed)

### What was done

- **Root-caused the recurring full-suite flake** (previously dismissed as a parallel-load flake in the Task 7 entry). Investigation of the pub-cache sources established the mechanism:
  - `sqflite_common` 2.5.17, `factory_mixin.dart`: with the default `singleInstance != false`, `openDatabase(path)` consults a per-path cache map `databaseOpenHelpers[path]`; if an existing helper is present it reuses that helper's already-open database (`SqfliteDatabaseOpenHelper.openDatabase()` returns `sqfliteDatabase` when `isOpen`).
  - All ten DB-using test files open the same key — `ffi.inMemoryDatabasePath` = `':memory:'` — so a later `_openInMemory()` could receive an earlier test's migrated connection, and `AppDatabase.migrate` then threw `table claims already exists`. The FFI layer itself (`sqflite_common_ffi` 2.4.7) opens a fresh native in-memory DB per call, confirming the sharing originates at the helper-cache layer.
  - The second failing test (missing `'CLM-NTF'`) is the same contention class: under parallel load the FFI isolate's queue is slow enough that the details screen's initial load had not resolved when the bare pump loop ended.
- **Fix** ([`test/widget_test.dart`](test/widget_test.dart)):
  - `_openInMemory()` now opens with `options: ffi.OpenDatabaseOptions(singleInstance: false)` — bypasses the helper cache, guarantees a fresh native DB per test (documented in the doc comment).
  - `settle()` bound raised 300 → 450 iterations (~9 s real time) to absorb parallel-load FFI latency.
  - Both notification-routing tests now poll for their final assertion target (`'CLM-NTF'` / `S.claimNotFound`) via the bounded settle loop instead of asserting right after a fixed pump count.

### Verification gate (fresh evidence — full prompt §Verification pass)

| Check | Command | Result |
|---|---|---|
| Formatter | `dart format --set-exit-if-changed lib test` | **clean** ("Formatted 52 files (0 changed)") |
| Static analysis | `flutter analyze` | **No issues found!** |
| Tests — run 1 | `flutter test` | **All tests passed, 119/119** (previously failing pair now green) |
| Tests — run 2 (load confidence) | `dart format --set-exit-if-changed lib test && flutter analyze && flutter test` | **All tests passed, 119/119** again; formatter still 0 changed |
| Android debug build | `flutter build apk --debug` | **√ Built `build\app\outputs\flutter-apk\app-debug.apk`** (Gradle `assembleDebug`, ~46 s) |

### Notable fixes this phase

- First fix attempt used `ffi.SqfliteOpenDatabaseOptions(...)` — that class is internal to sqflite_common and not exported; the public API is the abstract `OpenDatabaseOptions` with a factory constructor (verified in `sqlite_api.dart`). Corrected before re-running.
- The Task 7 entry's "flake, not a regression" note is superseded by this root cause: it was deterministic shared-state behavior of the sqflite_common helper cache, exposed by parallel scheduling.

### Phase 4 status

**COMPLETE.** All prompt §Verification items have fresh evidence (attach+reopen image/PDF via widget tests; persistence across restart via e2e harness; safe delete cleanup; export→restore round-trip incl. wrong-password/corrupt fail-closed; no network transmission — production manifest INTERNET-free and audit-pinned; formatter/analyze/tests/APK all green). Handoff docs updated: [`IMPLEMENTATION_PROGRESS.md`](IMPLEMENTATION_PROGRESS.md) checklist fully checked (APK item now `[x]`), flake root cause recorded under Known issues, README security section in place. No security certification or legal-compliance claim is made anywhere.

### Exact next step

Phase 5 per [`PROMPT_5_FINAL_QA_AND_APK.md`](PROMPT_5_FINAL_QA_AND_APK.md): full QA pass against spec §17–§20, fix any findings, and produce the final debug APK with verified evidence (on-device items — attachment open, notification delivery, backup file sharing — remain to be exercised where a device/emulator is available).

---

## 2026-11-12 (final) — Phase 5 complete: QA pass, two bug fixes (TDD), release APK, on-device verification, handoff docs

Executed `PROMPT_5_FINAL_QA_AND_APK.md` natively in-session. Ledger: `.superpowers/sdd/PROMPT_5_FINAL_QA_AND_APK.md/progress.md`. TDD per fix: RED → verify fail → GREEN → verify pass. All evidence below is from commands actually run this session.

### Task 1 — Verification gate (fresh baseline)

| Check | Command | Result |
|---|---|---|
| Formatter | `dart format --set-exit-if-changed lib test` | **clean** ("Formatted 52 files (0 changed)") |
| Static analysis | `flutter analyze` | **No issues found!** |
| Tests (full suite) | `flutter test` | **All tests passed, 119/119** (log: `.superpowers/sdd/PROMPT_5_FINAL_QA_AND_APK.md/test-run-1.log`) |

### Task 2 — Independent acceptance audit vs spec §17–§20

Re-verified from source + fresh runs rather than trusting phase reports. Findings: two real bugs (below); everything else confirmed green — claims CRUD/search/filters/dashboard counts/persistence, atomic status history, reminder flows incl. permission-denied path and tap routing, attachment attach/open/delete cleanup, export→restore round-trip with wrong-passphrase/corrupt fail-closed, privacy posture (audit-pinned), light/dark + RTL coverage in every screen test.

### Task 3 — Bug fixes (TDD red → green)

**Bug 1 — `attachFile` force-unwrap of nullable base dir.**
`ClaimActions.attachFile` computed the stored file size via `File('${svc.baseDir!.path}/$relativePath')` — a contract violation on the null-baseDir construction path (`baseDir == null` is legal; `storeDir()` resolves it lazily). Fix: new null-safe [`AttachmentFileService.storedFileFor(String relativePath)`](lib/features/attachments/attachment_file_service.dart) (resolves through `storeDir()` + `_resolveGuarded`, same traversal guard as every other accessor); `attachFile` now calls `(await svc.storedFileFor(relativePath)).lengthSync()`.
- RED: new test "storedFileFor resolves a stored row without force-unwrapping baseDir" in [`test/features/attachment_file_service_test.dart`](test/features/attachment_file_service_test.dart) — failed before the method existed.
- GREEN: passes; full suite green after.

**Bug 2 — stale OS alarms survive restore.**
After `restoreFrom` swapped the DB, pre-restore pending alarms could still fire (pointing at claims that no longer exist). Fix: extended [`ReminderScheduler`](lib/core/notifications/reminder_scheduler.dart) with `Future<void> reconcile(List<Reminder> enabledReminders)`; production impl in [`NotificationService.reconcile`](lib/core/notifications/notification_service.dart) cancels all pending then reschedules future-enabled reminders. Wired into the post-restore path: `ClaimTrackerApp` gained a final injectable `scheduler` field (defaults to the production singleton), and `reconnectAfterRestore()` in [`main.dart`](lib/main.dart) now calls `scheduler.reconcile(await RemindersRepository(fresh).allEnabled())` inside try/catch — best-effort, so a failing scheduler never breaks the restore.
- RED: new file [`test/features/restore_reconcile_test.dart`](test/features/restore_reconcile_test.dart) (3 tests: reconcile receives exactly the enabled reminders from the fresh DB; disabled reminders excluded; a throwing scheduler does not break the post-restore flow) — failed before wiring existed.
- GREEN: all 3 pass; three existing `FakeScheduler`s updated to record `reconcile` calls.

**Green-phase compile/lint fallout (fixed, re-verified):**
- `main.dart`: non-final `scheduler` field broke the `const ClaimTrackerApp` constructor → made it `final`.
- [`claim_actions.dart`](lib/features/claims/claim_actions.dart): removed now-unused `import 'dart:io';` after switching to `storedFileFor()`.
- Formatter drift on 3 touched files → re-ran `dart format`; subsequent check clean.

### Task 4 — Release APK + on-device verification

| Check | Command / evidence | Result |
|---|---|---|
| Privacy audit (manual re-check) | search of `lib/` for `print(`/`debugPrint(`/`log(`; pubspec scan for network packages; manifest read | **0 logging calls, 0 network package imports** (`http`/`dio`/sockets absent), production manifest has only `SCHEDULE_EXACT_ALARM` + a `PROCESS_TEXT` `<queries>` entry — **no INTERNET permission**. `url_launcher` used solely for user-initiated external attachment opens (spec §12). |
| Release build | `flutter build apk --release` | **√ Built** in ~70 s → `build\app\outputs\flutter-apk\app-release.apk` |
| Artifact verified | `dir build\app\outputs\flutter-apk\app-release.apk` | file exists — **57,520,895 bytes (54.9 MB)**, 11/12/2026 06:56 AM |
| Device | `adb devices` (full path `C:\Users\Majesty\AppData\Local\Android\sdk\platform-tools\adb.exe`; adb not on PATH) | **emulator-5554** — sdk gphone64 x86_64, Android 17 / API 37 |
| Install | `adb -s emulator-5554 install -r app-release.apk` | "Performing Streamed Install" → **Success** |
| Launch + crash check | `am start com.claimtracker.claim_tracker/.MainActivity`; logcat filtered to our PID 3910 | "Displayed ... +1s341ms", "Fully drawn ... +1s341ms"; libflutter.so/libdartjni.so loaded; **no FATAL EXCEPTION in our process** (the 8 FATAL lines in the buffer all belong to a different pre-installed app, `com.example.claimstracker`, PIDs 4047–5350) |
| Log PII scan | pattern search of our log lines for phone/name/passphrase shapes | **no personal data found** |

### Task 5 — Handoff docs + final report

- [`IMPLEMENTATION_PROGRESS.md`](IMPLEMENTATION_PROGRESS.md): Phase 5 completed-work section, full acceptance checklist (all `[x]`), known limitations, next action = none.
- This entry in [`WORK_LOG.md`](WORK_LOG.md).
- [`README.md`](README.md): install instructions for the release APK + signing status + known limitations appended.
- SDD ledger `.superpowers/sdd/PROMPT_5_FINAL_QA_AND_APK.md/progress.md`: Tasks 2–5 closed with evidence.

### Notable findings this phase

- **False-positive crash scare**: logcat showed 8 FATAL EXCEPTIONs — attributed by PID to `com.example.claimstracker` (a different app), not ours. Always attribute crashes by package/PID before concluding.
- **adb on Windows**: not on PATH; resolve via `android/local.properties` → `sdk.dir`, then call the full path with cmd.exe quoting (`"C:\...\adb.exe" -s emulator-5554 ...`). PowerShell-style `& "path"` and `%VAR%` expansion both fail in this shell.
- **Signing status (stated, not invented)**: release buildType uses `signingConfigs.getByName("debug")` — the APK is signed with the debug keystore. Fine for sideloading; a Play upload needs a real keystore + `signingConfigs.release`.

### Phase 5 status

**COMPLETE.** Formatter clean, analyzer clean, **123/123 tests passing**, release APK built and file-verified (57,520,895 bytes), installed and launched on emulator-5554 (Android 17 / API 37) with no crash in our process and no PII in logs. All five phases of the project are done; handoff docs updated.

---

## 2026-11-12 — iOS target + unsigned IPA workflow (owner decision)

**Scope change**: the owner asked for an iOS build they can sideload. Spec §2 and the README boundaries were updated (iOS in scope; Android-only requirements stay Android-only).

**Environment**: Windows 11, Flutter 3.47.9 / Dart 3.13.7. iOS cannot be built on Windows, so the build runs on GitHub Actions macOS runners.

### Changes

- `flutter create --platforms=ios --org com.claimtracker --project-name claim_tracker .` → `ios/` (bundle id `com.claimtracker.claimTracker`, deployment target 15.0, SwiftPM plugin package, UIScene template). The tool also added `ios/**`, `android/**`, `build/**` to the analyzer excludes and rewrote `.metadata`'s platform list (Android entry restored by hand).
- Found by reading the code: on iOS `areNotificationsEnabled()` always returned false (Android-only implementation), so reminders would never be scheduled and the "denied" dialog would show on every save. Fixed with `IOSFlutterLocalNotificationsPlugin.checkPermissions()/requestPermissions()`, Darwin init settings (no launch prompt), and `DarwinNotificationDetails` (foreground banner/sound). Exact-alarm + battery helpers return true on iOS; Settings hides those rows on iOS (`defaultTargetPlatform`).
- iOS cannot open sandboxed `file://` URLs in another app via url_launcher → added a QuickLook previewer on the `com.claimtracker/files` channel in `AppDelegate.swift`; Dart routes `file:` URIs there on iOS only.
- `Info.plist`: `CFBundleLocalizations` en/ar, `NSPhotoLibraryUsageDescription`, `ITSAppUsesNonExemptEncryption=false`.
- `.github/workflows/ios-build.yml`: Linux job (`pub get`, `analyze`, `test`) → macOS job (`flutter build ios --release --no-codesign --build-number=<run#>`, zip `Payload/Runner.app` → `ClaimTracker-unsigned.ipa`, upload artifact).
- `.gitignore`: `tools/*.bin|*.txt|*.xml` (the DB copy holds 5 claim rows) and `*.ipa`, `Payload/`.

### Flaky test found and fixed

`test/core/backup_service_test.dart` "restore with wrong passphrase…" failed in 2 of 3 full-suite runs but passed alone. Causes: `expect(() => asyncCall, throwsA(...))` without `await expectLater` (assertions ran before the restore finished), and a scan of the shared system temp dir for `ct_restore*` that saw staging dirs from other test files running in parallel. Fix: `await expectLater(...)` inside `IOOverrides.runZoned(getSystemTempDirectory: ...)` pointing at a per-test temp root, and assert on that root only. Production code untouched.

### Verification (actually run)

| Check | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` ×3 after the flaky-test fix | 150/150 each run |
| New test `iOS: Android-only exact-alarm and battery rows are hidden` | passes |
| `flutter test` full, final (after `dart format lib test`) | 151/151 passed |
| `flutter build ios` / IPA | **not run** — needs macOS; first real check is the CI run |
| Swift code (`AppDelegate.swift`) | **not compiled locally** — compiled for the first time by CI |
