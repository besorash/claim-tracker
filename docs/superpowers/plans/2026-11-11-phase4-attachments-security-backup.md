# Phase 4 — Attachments, Security & Encrypted Backup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship spec §12–§16 — claim attachments in app-private storage, privacy hardening, and a passphrase-encrypted local backup/restore with safe staging-and-swap.

**Architecture:** Pure-Dart crypto core (PBKDF2-HMAC-SHA256 → AES-256-CTR + HMAC-SHA256 encrypt-then-MAC) built on `pointycastle 4.0.0` (already pinned; APIs verified against the local pub cache). A `BackupService` serializes DB bytes + attachment files into one versioned binary format, exports to a user-chosen file, and restores via decrypt → stage in temp dir → validate (integrity_check + row/file cross-checks) → swap. Attachments use an existing schema-v1 table (`attachments`, FK cascade already present); `AttachmentFileService` owns physical files under the app documents directory; picker results are copied immediately so no temporary URI is ever relied on.

**Tech Stack:** Flutter 3.47.9 / Dart 3.13.7, sqflite (+sqflite_common_ffi for host tests), file_picker 13.x (Android impl verified: picks are copied to app-private cache and returned as absolute paths), url_launcher 6.3.3 (added this session; resolves offline), pointycastle 4.0.0, path_provider.

**Spec:** `MASTER_PROJECT_SPEC.md` §12 (attachments), §14 (privacy/security), §15 (backup/restore), §16 (settings). Phase prompt: `PROMPT_4_ATTACHMENTS_SECURITY_BACKUP.md`.

## Global Constraints

- Android only; Arabic UI strings ONLY via the `S` class in [`lib/core/l10n/app_strings.dart`](../../../lib/core/l10n/app_strings.dart) — no literal Arabic in widget code (spec §3.4).
- No network transmission of claim data, no analytics/telemetry (spec §14). Manifest must keep NO `INTERNET` permission (verified absent today).
- All app data stays in app-private storage: DB at sqflite's databases path; attachments under `<documents>/attachments`; backup staging under the temp dir. Never write to shared/public storage.
- No hardcoded keys or passphrases anywhere (spec §14). Passphrase is user-supplied per operation and never persisted.
- Persist-before-pop ordering for every mutating dialog (established Phase 2–3 pattern): await the full persist chain before `Navigator.pop()`.
- No non-functional buttons (spec §3.3); render conditional actions only when their precondition holds.
- Timestamps stored as INTEGER UTC ms; seed test data at millisecond precision (`DateTime.utc(y,m,d,h,min,s)`).
- Host tests: FFI SQLite via `sqflite_common_ffi` with `PRAGMA foreign_keys = ON`; real file I/O inside `tester.runAsync`; settle on strong non-UI signals (Phase 2/3 harness rules in `.superpowers/sdd/*/progress.md`).
- **No git repository** (verified): replace every "Commit" step with a dated WORK_LOG.md entry per spec §18.
- Do not claim encryption compliance/certification; document the design and its limits honestly (spec §14, §18).

## Verified environment facts (do not re-derive)

- `pointycastle 4.0.0` in pub cache: `PBKDF2KeyDerivator(Mac)` + `init(Pbkdf2Parameters(salt, iterationCount, desiredKeyLength))` + `deriveKey(inp, off, out, off)` (lib/key_derivators/pbkdf2.dart, api at lib/key_derivators/api.dart); `HMac(Digest)` + `init(KeyParameter)` (lib/macs/hmac.dart); `AESFastEngine().init(bool, KeyParameter)` / `.processBlock(...)` (lib/block/aes_fast.dart); `CTRStreamCipher(BlockCipher).init(bool, ParametersWithIV)` (lib/stream/ctr.dart, lib/stream/sic.dart); `SHA256Digest` (lib/digests/sha256.dart).
- `crypto 3.0.8` has NO PBKDF2 — use pointycastle for KDF.
- `file_picker 13.x` → `android_file_picker 2.1.5`: `processFiles()` copies every content-URI pick into `context.cacheDir` (`openFileStream`, FileUtils.kt) and returns absolute paths; `PlatformFile.path` is therefore a readable local file (verified in source).
- Schema v1 already has the `attachments` table with `claim_id REFERENCES claims(id) ON DELETE CASCADE` and `relative_path UNIQUE` — no migration needed this phase.
- `AppConstants.backupFormatVersion = 1`, `backupMagic = [0x43,0x54,0x42,0x4B]` ("CTBK") already reserved in [`lib/core/constants/app_constants.dart`](../../../lib/core/constants/app_constants.dart).
- Generic notification text already implemented (`AppConstants.genericReminderTitle/Body`, used by `NotificationService.scheduleReminder`) — Phase 4 only verifies it.
- `url_launcher 6.3.3` added to pubspec this session (resolves offline; needed for opening PDFs in a system viewer).

## Encryption design (documented per spec §15)

**KDF:** PBKDF2-HMAC-SHA256, salt = random 16 bytes (per backup), iterations = 100,000. Output 64 bytes: first 32 = AES key, last 32 = HMAC key.
**Cipher:** AES-256 in CTR mode (stream cipher — no padding; IV = random 16 bytes per backup).
**Integrity/auth:** Encrypt-then-MAC: `HMAC-SHA256(macKey, header || ciphertext)`, 32-byte tag appended. Restore verifies the MAC with constant-time comparison BEFORE decrypting → wrong password and corruption both fail closed.
**Nothing is stored about the passphrase.** Salt + iteration count travel in the plaintext header (standard for PBKDF2). No key material ever touches disk or secure storage, so there is no Keystore integration to build; `flutter_secure_storage` stays reserved for a future app-lock (spec §14: lower priority, not this phase).
**Database encryption evaluation (spec §14):** SQLCipher/Drift are NOT available in the offline pub cache and would force re-testing the entire Phase 1–3 DB layer against a new native dependency. Decision: rely on Android app sandbox + app-private paths for at-rest protection; backups are encrypted with the design above. Recorded as a known limitation, not claimed as full-DB encryption (spec §18 honesty rule).

## Backup format v1 (big-endian integers)

```
offset  size  field
0       4     magic "CTBK" (AppConstants.backupMagic)
4       2     u16 format version (= AppConstants.backupFormatVersion = 1)
6       16    salt
22      4     u32 PBKDF2 iterations
26      8     u64 payload length N
34      N     ciphertext (AES-CTR over the serialized payload, IV prepended: first 16 bytes of ciphertext region are the IV)
34+N    32    HMAC-SHA256 tag over bytes [0 .. 34+N)
```

**Payload serialization** (the plaintext that gets encrypted):
```
u64 dbBytesLength, then dbBytes
u32 attachmentCount, then per attachment:
   u32 originalNameLen + UTF-8 originalName
   u32 relativePathLen  + UTF-8 relativePath
   u32 mimeTypeLen      + UTF-8 mimeType
   u64 dataLength       + file bytes
```

## File structure (new/modified)

| File | Responsibility |
|---|---|
| Create `lib/core/security/backup_crypto.dart` | Pure-Dart KDF/cipher/MAC: `encryptFileBytes`, `decryptFileBytes`, version check, error types. No I/O, no Flutter imports → trivially host-testable. |
| Create `lib/core/security/backup_service.dart` | Payload (de)serialization, export to file, staged restore with validation + swap. Depends on `AppDatabase`, `AttachmentFileService`. |
| Create `lib/features/attachments/attachment_file_service.dart` | Physical file store: import/copy into `<documents>/attachments`, resolve+guard paths, safe delete. Injectable base dir for tests. |
| Create `lib/features/attachments/attachment_picker_seam.dart` | `AttachmentPicker` abstract + production impl over `FilePicker`; fake in widget tests (no method channels on host). |
| Modify `lib/core/database/attachments_repository.dart` | Add `listAll()` (needed by backup export) — keep existing API. |
| Modify `lib/features/claims/claim_actions.dart` | `deleteClaim` also deletes the claim's attachment files; new `attachFile(claimId, sourcePath)` flow (copy → insert row). |
| Modify `lib/features/claims/claim_details_screen.dart` | Attachments section: list, add (picker), open/preview (image in-app, PDF/others via url_launcher), delete with confirmation. |
| Modify `lib/features/settings/settings_screen.dart` | Backup & restore card (export/restore flows + passphrase dialogs) and security-info card (local-only statement, encryption summary, PDPL confirmation note). |
| Modify `lib/core/l10n/app_strings.dart` | New Arabic strings for attachments + backup/security sections. |
| Create tests: `test/core/backup_crypto_test.dart`, `test/core/backup_service_test.dart`, `test/features/attachment_file_service_test.dart`, `test/features/claim_actions_attachments_test.dart`, extend `test/features/claim_details_screen_test.dart` and `test/features/settings_screen_test.dart`. |

## Review Focus

1. **Wrong passphrase on restore must not touch existing data** — user expects their current claims to survive a failed restore. → Task 2 test: "restore with wrong passphrase leaves current db rows AND attachment files intact".
2. **Corrupt/truncated archive fails before any swap** — a flipped byte mid-payload must abort with `corruptArchive` and leave the live DB openable. → Task 2 test: "flipped payload byte rejects restore, existing data untouched".
3. **Attachment delete never escapes the store** — a crafted `relative_path` containing `..` segments must be refused, not resolved outside `<documents>/attachments`. → Task 3 test: "deleteFile refuses traversal paths and leaves foreign files intact".
4. **Claim deletion cleans exactly its own attachment files** — other claims' files must survive. → Task 4 test: "deleteClaim removes only that claim's files".
5. **Restored attachments stay openable; a missing file degrades gracefully** — after restore, every row's file exists and opens; if one is absent the UI shows an Arabic error state instead of crashing. → Task 2 + Task 5 tests.

---

### Task 1: BackupCrypto core (KDF + AES-CTR + HMAC)

**Files:**
- Create: `lib/core/security/backup_crypto.dart`
- Test: `test/core/backup_crypto_test.dart`

**Interfaces:**
- Consumes: pointycastle 4.0.0 (verified APIs above), `AppConstants.backupMagic`, `AppConstants.backupFormatVersion`.
- Produces (exact signatures — later tasks rely on these):
  - `sealed class BackupError implements Exception { final String message; }` with subclasses `WrongPassphraseError`, `CorruptArchiveError`, `IncompatibleVersionError` (each has a const constructor taking the Arabic-safe English-free detail string).
  - `class BackupCrypto { static Uint8List encrypt(String passphrase, List<int> plaintext); static Uint8List decrypt(String passphrase, List<int> fileBytes); static int formatVersionOf(List<int> fileBytes); }` — `formatVersionOf` parses ONLY the header (magic+version) and throws `CorruptArchiveError`/`IncompatibleVersionError`; it never touches the passphrase.
  - Header layout constants live in this file: `_kSaltLen=16`, `_kIvLen=16`, `_kMacLen=32`, `_kIterations=100000`.

- [ ] **Step 1: Write failing tests** in `test/core/backup_crypto_test.dart`:
  - `round-trips arbitrary bytes` — encrypt a 1 MiB pseudo-random payload (seeded LCG, deterministic), decrypt with same passphrase, expect identical bytes.
  - `rejects wrong passphrase` — decrypt with a different passphrase throws `WrongPassphraseError`.
  - `rejects corrupted ciphertext` — flip one byte at the middle of the ciphertext region; decrypt throws (`CorruptArchiveError` or `WrongPassphraseError` both acceptable — assert it is a `BackupError`, not success, and NOT an unhandled exception).
  - `detects truncated file` — drop last 10 bytes → throws `BackupError`.
  - `rejects unknown version before decryption` — copy a valid file, overwrite the u16 at offset 4 with `99`; `formatVersionOf` throws `IncompatibleVersionError` (and `decrypt` does too).
  - `independent KDF cross-check` — derive the key for fixed passphrase/salt/iterations using an inline reference PBKDF2-HMAC-SHA256 loop written directly in the test with pointycastle's `HMac(SHA256Digest())` (no `PBKDF2KeyDerivator`), and assert it equals the first 32 bytes of a key derived via `BackupCrypto`'s internal KDF helper — exposes the KDF as `static Uint8List deriveKeys(String passphrase, List<int> salt, int iterations)` returning 64 bytes so the test can call it.
  - `different salts produce different keys for same passphrase`.

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/core/backup_crypto_test.dart`
Expected: FAIL — "backup_crypto.dart not found" (compile error).

- [ ] **Step 3: Implement `BackupCrypto` in `lib/core/security/backup_crypto.dart`**

Approach notes (the tests + signatures above determine the rest):
- KDF via `PBKDF2KeyDerivator(HMac(SHA256Digest()))`, `init(Pbkdf2Parameters(salt, iterations, 64))`, `deriveKey(passphraseUtf8, 0, out, 0)`.
- Encrypt: random salt(16)+IV(16) via `dart:math Random.secure()`; build header per format table (magic from `AppConstants.backupMagic`); ciphertext = IV ‖ AES-CTR keystream XOR (implement CTR by looping `AESFastEngine().processBlock` over 16-byte counter blocks — pointycastle's `CTRStreamCipher` also works: `init(true, ParametersWithIV(KeyParameter(key), iv))` then process in 16-byte chunks); MAC = `HMac(SHA256Digest())` with macKey over header‖ciphertext.
- Decrypt: parse+validate header (lengths, magic, version == `AppConstants.backupFormatVersion` else `IncompatibleVersionError`), recompute KDF, verify MAC with a constant-time compare helper (`_constantTimeEquals`) → mismatch = `WrongPassphraseError`; then decrypt; any structural failure = `CorruptArchiveError`.
- No Flutter imports; no logging of passphrase/keys (spec §14).

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/core/backup_crypto_test.dart` → Expected: PASS (7/7).
Run: `flutter analyze` → Expected: No issues found.

- [ ] **Step 5: WORK_LOG entry** — append a dated Phase 4 entry noting Task 1 complete, the encryption design summary (KDF/cipher/MAC + parameter values), and test evidence.

---

### Task 2: BackupService — export, staged restore, validation

**Files:**
- Create: `lib/core/security/backup_service.dart`
- Modify: `lib/core/database/attachments_repository.dart` (add `Future<List<Attachment>> listAll()`)
- Test: `test/core/backup_service_test.dart`

**Interfaces:**
- Consumes: `BackupCrypto` (Task 1), `AppDatabase`, `AttachmentsRepository.listAll()` → `List<Attachment>` (model in [`lib/core/models/attachment.dart`](../../../lib/core/models/attachment.dart)), `AttachmentFileService` (Task 3 — but this task only needs its two methods, defined here so Task 3 implements to them):
  - `class AttachmentFileService { AttachmentFileService({Directory? baseDir}); Future<String> importFile(String sourcePath, {String originalName = ''}) → relative path; File fileFor(Attachment a); Future<void> deleteFile(Attachment a); }`
- Produces:
  - `class BackupService { BackupService(this.db, this.files); Future<File> exportTo(File destination, String passphrase); Future<RestoreReport> restoreFrom(File source, String passphrase); }`
  - `class RestoreReport { final int claims; final int attachmentsRestored; }` (counts for the UI success dialog).
  - Throws Task 1's `BackupError` subtypes on failure.

- [ ] **Step 1: Write failing tests** in `test/core/backup_service_test.dart`. Harness: FFI in-memory or temp-file DB via existing pattern from [`test/database/repositories_test.dart`](../../../test/database/repositories_test.dart) (`ffi.databaseFactory = ffi.databaseFactoryFfi;` + `PRAGMA foreign_keys = ON`), real temp dirs for attachments (create under `Directory.systemTemp.createTempSync()`).
  - `export produces a file that is not plaintext` — seed 1 claim + 2 attachment files with known bytes; export; assert file exists, starts with "CTBK", and does NOT contain the customer name UTF-8 bytes.
  - `restore into clean state reproduces claims, history, reminders, attachments` — fresh empty DB + empty store dir; restore from the exported file; assert claim row fields match, status_history rows match (seed one via `StatusHistoryRepository.changeStatus`), reminder row matches, and each attachment's file bytes equal the originals.
  - **Review Focus #1:** `restore with wrong passphrase leaves current db rows AND attachment files intact` — seed live data + a live attachment file; attempt restore with wrong passphrase → expect `WrongPassphraseError`; then assert live claim still readable via `db.claimById`, live attachment file bytes unchanged, and NO staging leftovers in the temp dir.
  - **Review Focus #2:** `flipped payload byte rejects restore, existing data untouched` — flip one ciphertext byte; expect a `BackupError`; live data intact (same assertions as above).
  - `incompatible version is rejected before touching data` — overwrite header u16 with 99 → `IncompatibleVersionError`, live data intact.
  - **Review Focus #5:** `restore validates every attachment row has its file; a missing file aborts safely` — hand-craft a valid backup (export, then re-encrypt is not needed: instead export from a DB whose attachments table references a relative path with no backing file — insert the row directly via SQL), restore → expect failure (`CorruptArchiveError`) and live data intact.
  - `restore swaps atomically after validation` — after a successful restore, assert old attachment files (from the pre-restore seed) are gone from the store dir and new ones present (no duplicate accumulation).

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/core/backup_service_test.dart`
Expected: FAIL — "backup_service.dart not found".

- [ ] **Step 3: Implement `BackupService` in `lib/core/security/backup_service.dart`**

Approach notes (signatures + tests determine the rest):
- Export: read DB file bytes via `db.rawDb.path` (sqflite exposes it; for FFI temp-file DBs this is a real path — use that, not in-memory), serialize payload per format table using `ByteData`/manual big-endian writes, `BackupCrypto.encrypt`, write to destination.
- Restore order (spec §15: validate before replacing):
  1. `formatVersionOf` check → decrypt with passphrase (MAC first) — failures throw BEFORE any filesystem mutation of live data.
  2. Parse payload into staged files under a fresh temp dir (`Directory.systemTemp.createTempSync('ct_restore')`): `db.sqlite` + attachment files at their relative paths; while parsing, enforce that every declared length fits in the remaining buffer (else `CorruptArchiveError`).
  3. Open the staged DB with the FFI/sqflite factory, run `PRAGMA integrity_check` (expect 'ok'), count rows per table, and verify each `attachments.relative_path` has a non-empty file on disk → else delete staging dir + throw `CorruptArchiveError`.
  4. Swap: close live DB (`db.close()`), delete old DB file, move staged db into the original path; replace store contents — delete existing files under the attachments dir, then move staged files in (Task 3's service exposes a `Future<void> replaceStoreFrom(Directory source)` helper for this).
  5. Reopen is the caller's job (`AppDatabase.open()`); return `RestoreReport` with counts read from the staged DB before swap.
- All failure paths after step 2 clean up their staging dir (try/finally).

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/core/backup_service_test.dart` → Expected: PASS (7/7).
Run: `flutter analyze` → No issues found.

- [ ] **Step 5: WORK_LOG entry** — Task 2 complete, restore-order rationale, test evidence.

---

### Task 3: AttachmentFileService — private store + safe cleanup

**Files:**
- Create: `lib/features/attachments/attachment_file_service.dart`
- Test: `test/features/attachment_file_service_test.dart`

**Interfaces:**
- Consumes: `path_provider` (`getApplicationDocumentsDirectory()`), `Attachment` model.
- Produces (exact — Task 2 already codes against these):
  - `class AttachmentFileService { const AttachmentFileService({this.baseDir}); final Directory? baseDir; Future<Directory> storeDir(); Future<String> importFile(String sourcePath, {String originalName = ''}) → relative path string; File fileFor(Attachment a); bool isInsideStore(String absolutePath); Future<void> deleteFile(Attachment a); Future<void> replaceStoreFrom(Directory source); }`
  - `storeDir()` = `baseDir ?? (await getApplicationDocumentsDirectory())/attachments`, created if missing.

- [ ] **Step 1: Write failing tests** in `test/features/attachment_file_service_test.dart` (all with an injected temp `baseDir`; no method channels):
  - `importFile copies bytes and returns a relative path` — source file with known content; import; assert returned string has no leading slash, the stored file's bytes equal the source, and the original source file is untouched.
  - `importFile sanitizes hostile names` — originalName `../../evil.png` → stored name contains no `..` segments (assert `isInsideStore(fileFor(...).path)` true and path does not escape baseDir).
  - **Review Focus #3:** `deleteFile refuses traversal paths and leaves foreign files intact` — build an `Attachment(relativePath: '../outside.txt')`; create a real file OUTSIDE the store with that name; call `deleteFile` → expect it to throw (or no-op) AND the outside file still exists.
  - `deleteFile removes exactly the stored file`.
  - `fileFor resolves inside the store only` — traversal relativePath → `isInsideStore(fileFor(a).path)` false.
  - `replaceStoreFrom swaps contents without leaking old files` — seed two old files, source dir has one new file; replace; assert old gone, new present with correct bytes.

- [ ] **Step 2: Run to verify failure** → `flutter test test/features/attachment_file_service_test.dart`, Expected: FAIL (file not found).

- [ ] **Step 3: Implement the service.**
  - Name generation for imports: `${DateTime.now().millisecondsSinceEpoch}-${sanitized}` where sanitized = originalName with every path separator and `..` stripped, fallback `'file'`; on collision append a counter.
  - Guard helper `_resolveGuarded(String relativePath)`: split on `/`, reject any segment that is `..` or absolute → throw `ArgumentError`. Every public method that touches disk goes through it (spec §12: "avoiding accidental deletion of unrelated files").
  - No logging of file contents or customer names (only the generated store name, which is safe).

- [ ] **Step 4: Run to verify pass** → Expected: PASS (6/6); `flutter analyze` clean.

- [ ] **Step 5: WORK_LOG entry.**

---

### Task 4: Attach flow + claim-delete cleanup in ClaimActions

**Files:**
- Modify: `lib/features/claims/claim_actions.dart`
- Create: `lib/features/attachments/attachment_picker_seam.dart`
- Test: `test/features/claim_actions_attachments_test.dart`

**Interfaces:**
- Consumes: `AttachmentsRepository`, `AttachmentFileService`, `AppDatabase`.
  - Picker seam (new file): `abstract class AttachmentPicker { Future<List<PlatformFile>> pick({required FileType type}); }` + `class FilePickerAttachmentPicker implements AttachmentPicker` wrapping `FilePicker.platform.pickFiles(type: type, withData: false)`; tests inject a fake returning synthetic `PlatformFile`s backed by real temp files (implement the abstract members directly — no method channels).
- Produces on `ClaimActions`:
  - `Future<Attachment> attachFile(int claimId, String sourcePath, {String originalName = '', String mimeType = ''})` — copy into store → insert row → return stored `Attachment`. On DB insert failure, delete the copied file (no orphans).
  - `deleteClaim` extended: before `_claims.delete(claimId)`, list that claim's attachments and `files.deleteFile(a)` each (best-effort per file, mirroring `_safeCancel` style — one failing file must not block deletion of the rest or the row).

- [ ] **Step 1: Write failing tests** in `test/features/claim_actions_attachments_test.dart` (FFI DB + temp store dir; fake picker where needed):
  - `attachFile stores bytes, inserts a row linked to the claim, and returns it` — assert row fields (claimId, originalName, sizeBytes) and file existence.
  - `attachFile cleans up the copied file when the insert fails` — force failure by inserting with an invalid claim id after FK check… simpler: use a DB where the attachments insert throws (e.g., close the DB mid-call is flaky — instead make the test inject a store dir whose parent is read-only on host? Not portable). Ruling: implement cleanup via try/catch and test it by passing a source path that copies fine but then inserting into a claim id that does not exist → FK violation throws → assert no file remains in the store.
  - **Review Focus #4:** `deleteClaim removes only that claim's files` — two claims, one attachment each; delete claim A; assert A's file gone, B's file present with intact bytes, B's row intact.
  - `attachFile rejects a missing source path gracefully` — throws a typed error (use `ArgumentError`), no partial state.

- [ ] **Step 2: Run to verify failure** → Expected: FAIL (`attachFile` undefined).

- [ ] **Step 3: Implement.** Add an optional `AttachmentFileService files` parameter to the `ClaimActions` constructor (default null → existing tests keep passing; when null, `deleteClaim` skips file cleanup and `attachFile` throws `StateError`). Update the two production call sites in [`lib/features/claims/claim_details_screen.dart`](../../../lib/features/claims/claim_details_screen.dart) to pass a real instance.

- [ ] **Step 4: Run to verify pass** → Expected: PASS (4/4); full suite `flutter test` still green; `flutter analyze` clean.

- [ ] **Step 5: WORK_LOG entry.**

---

### Task 5: Attachments UI on claim details (list / add / open / delete)

**Files:**
- Modify: `lib/features/claims/claim_details_screen.dart`, `lib/core/l10n/app_strings.dart`
- Test: extend `test/features/claim_details_screen_test.dart`

**Interfaces:**
- Consumes: Task 4's `ClaimActions.attachFile/deleteClaim`, `AttachmentPicker` seam (inject via a new optional constructor param `picker` on `ClaimDetailsScreen`, defaulting to `FilePickerAttachmentPicker()`), `url_launcher`.
- Produces (UI contract for tests): section titled `S.attachmentsLabel`; each row shows original name + human size; add button key `Key('attach-add')`; per-row delete key `Key('attach-del-$id')`; open action = tap on the row.

New Arabic strings to add in `app_strings.dart` (exact keys):
- `attachmentsEmpty = 'لا توجد مرفقات بعد.'`
- `attachmentAdd = 'إضافة مرفق'`
- `attachmentOpenFailed = 'تعذّر فتح الملف. قد لا يوجد تطبيق على جهازك يفتح هذا النوع.'`
- `attachmentMissing = 'الملف غير موجود على الجهاز.'`
- `deleteAttachmentTitle = 'حذف المرفق؟'`, `deleteAttachmentBody = 'سيُحذف الملف من التخزين الخاص بالتطبيق نهائيًا.'`

- [ ] **Step 1: Write failing widget tests** (reuse the Phase 3 harness rules from `.superpowers/sdd/2026-11-11-phase3-statuses-and-reminders.md/progress.md`: explicit-duration pumps until route animation completes, strong settle signals, `runAsync` for I/O):
  - `shows empty state and add button when a claim has no attachments`.
  - `add flow: fake picker returns one file → row appears with its name; store contains the copied bytes` (settle on the row's Key appearing — absent until persist completes).
  - `tapping an image attachment opens an in-app preview dialog showing the file` (seed a tiny valid PNG byte pattern; assert a `Dialog`/preview widget appears, then close it).
  - `tapping a PDF attachment attempts url_launcher and shows the Arabic failure state when launch is unavailable on host` — inject a fake launcher seam: add optional param `openExternal: Future<bool> Function(Uri)` to the screen (default = real `urlLauncherOpen`); test passes one returning false → expect `S.attachmentOpenFailed` text.
  - `delete flow: confirm dialog → row gone AND store file deleted`.
  - **Review Focus #5:** `missing attachment file renders S.attachmentMissing instead of crashing` — insert a row whose backing file was removed; assert the label, and that add/delete still work for other rows.

- [ ] **Step 2: Run to verify failure** → Expected: FAIL (no attachments section).

- [ ] **Step 3: Implement.**
  - Load attachments in `_load()` via `AttachmentsRepository.listForClaim` alongside history/reminder.
  - Add button → `picker.pick(type: FileType.any)` → for each result with a non-null `path`: `mimeType = _mimeFromExtension(name)`, `actions.attachFile(...)`. MIME map (extension→type): jpg/jpeg/png/webp/gif/heic → image/*; pdf → application/pdf; doc/docx/xls/xlsx/ppt/pptx/txt/csv/md → their standard types; fallback `application/octet-stream` (spec §12 "other common document types where supported").
  - Open: images (`image/` prefix) → full-screen dialog with `Image.file(File(absPath))` + close button; everything else → `openExternal(Uri.file(absPath))`; false/unavailable → Arabic error snackbar/dialog. Missing file (checked via `File.existsSync`) → row shows `S.attachmentMissing`, tap is a no-op.
  - Delete: confirmation dialog (persist-before-pop), then repo.delete + files.deleteFile, refresh list.

- [ ] **Step 4: Run to verify pass** → Expected: new tests PASS; full suite green; `flutter analyze` clean; `dart format lib test --output=write` clean.

- [ ] **Step 5: WORK_LOG entry.**

---

### Task 6: Settings — backup/restore card + security info

**Files:**
- Modify: `lib/features/settings/settings_screen.dart`, `lib/core/l10n/app_strings.dart`
- Test: extend `test/features/settings_screen_test.dart`

**Interfaces:**
- Consumes: `BackupService` (Task 2), `AttachmentFileService`, `AppDatabase`; export destination via `FilePicker.platform.saveFile(...)` behind a seam — add optional constructor params to `SettingsScreen`: `backupService`, `pickSaveDestination: Future<String?> Function()`, `pickRestoreSource: Future<File?> Function()` (defaults wrap FilePicker; tests inject temp-dir closures).
- Produces (UI contract): card titled `S.settingsBackupRestore` with two buttons — keys `Key('backup-export')`, `Key('backup-restore')`; security card key `Key('security-info')`.

New Arabic strings:
- `backupExportAction = 'تصدير نسخة احتياطية مشفّرة'`
- `backupRestoreAction = 'استعادة من نسخة احتياطية'`
- `backupPassphraseTitle = 'عبارة مرور التشفير'`, `backupPassphraseConfirmTitle = 'تأكيد عبارة المرور'`
- `backupExportedOk = 'تم إنشاء النسخة الاحتياطية بنجاح.'`
- `restoreWarningTitle = 'استبدال البيانات الحالية؟'`, `restoreWarningBody = 'سيستبدل هذا الإجراء كل المطالبات والمرفقات الحالية بمحتوى النسخة. لا يمكن التراجع بعد التأكيد.'`
- `restoredOk = 'تمت الاستعادة: {claims} مطالبة و{attachments} مرفقًا.'` (format via replaceAll like the existing version string)
- `backupFailedWrongPassphrase = 'عبارة المرور غير صحيحة أو النسخة تالفة. لم تُعدَّل بياناتك الحالية.'`
- `securityInfoTitle = 'الخصوصية والأمان'`, `securityInfoBody = 'تُخزَّن جميع البيانات محليًا على جهازك فقط، دون أي إرسال عبر الشبكة أو تحليلات. النسخ الاحتياطي مشفَّر بعبارة مرورك (PBKDF2 + AES-256). تأكد قبل إدخال بيانات حقيقية من توافق التخزين المحلي مع سياسات جهة عملك ومتطلبات الخصوصية السعودية (PDPL) حيث ينطبق.'`

- [ ] **Step 1: Write failing widget tests:**
  - `renders backup card with both actions and the security info card`.
  - `export flow: passphrase + confirm dialogs → save destination picked → success text S.backupExportedOk appears; a file exists at the chosen path starting with CTBK` (inject real temp paths; settle on the success text — absent until export completes).
  - `restore flow: source picked → warning dialog → confirm → success text shows restored counts`.
  - `wrong passphrase shows S.backupFailedWrongPassphrase and does NOT show success` (settle on the failure text).
  - `passphrase mismatch between entry and confirmation blocks the export with no file written`.

- [ ] **Step 2: Run to verify failure** → Expected: FAIL.

- [ ] **Step 3: Implement.** Dialogs follow the existing Phase 3 pattern (StatefulBuilder + persist-before-pop). Export: passphrase dialog (obscured TextField) → confirm-passphrase dialog → `pickSaveDestination()` → `backupService.exportTo` → success/failure text state. Restore: `pickRestoreSource()` → warning dialog (explicit, spec §15) → passphrase dialog → `restoreFrom` → on success bump the shell's `_gen` so all destinations reload (add an optional `onDataRestored: VoidCallback?` param to `SettingsScreen`, wired by the shell in Task 7); on `BackupError` show the mapped Arabic message. Never log passphrases.

- [ ] **Step 4: Run to verify pass** → Expected: PASS; full suite green; analyze + format clean.

- [ ] **Step 5: WORK_LOG entry.**

---

### Task 7: Security hardening pass + shell wiring + docs

**Files:**
- Modify: `lib/app/home_shell.dart` (pass `onDataRestored: _bump` to SettingsScreen), `README.md`, `IMPLEMENTATION_PROGRESS.md`
- Test: create `test/core/security_audit_test.dart`

- [ ] **Step 1: Write failing audit tests** in `test/core/security_audit_test.dart`:
  - `notification text is generic (no claim fields)` — assert `AppConstants.genericReminderTitle/Body` contain none of the substrings from a seeded claim's customer name/mobile/claim number (seed via FFI DB, read constants, assert absence). This pins spec §14's lock-screen rule.
  - `manifest declares no INTERNET permission` — read `android/app/src/main/AndroidManifest.xml`, assert it does not contain `android.permission.INTERNET`.
  - `no sensitive logging in lib/` — scan all `lib/**/*.dart` for `print(`, `debugPrint(`, `log(` calls whose argument references a model field name from the deny-list (`customerName|customerMobile|nationalId|claimNumber|notes|passphrase`) → expect zero matches.
  - `no hardcoded key material` — scan `lib/` for hex-string literals longer than 32 chars assigned to variables named like `key|secret|iv|salt` (heuristic; expect zero).

- [ ] **Step 2: Run** → Expected: FAIL if any violation exists (fix the offending code, not the test); otherwise PASS.

- [ ] **Step 3: Wire shell + docs.**
  - `home_shell.dart`: add `onDataRestored: _bump` to the `SettingsScreen(...)` construction so a completed restore refreshes every destination (IndexedStack staleness rule from Phase 2).
  - `README.md`: add "Backup & restore" section — format v1 layout, KDF/cipher parameters, how to export/restore, what is NOT covered (no full-DB encryption at rest; no server upload by design), and the PDPL confirmation note.
  - `IMPLEMENTATION_PROGRESS.md`: mark Phase 4 sections as they verify (final update in Task 8).

- [ ] **Step 4: Run** → `flutter test` full suite green; `flutter analyze` clean.

- [ ] **Step 5: WORK_LOG entry** — audit results with the exact commands and outputs.

---

### Task 8: Full verification gate + handoff docs

**Files:**
- Modify: `IMPLEMENTATION_PROGRESS.md`, `WORK_LOG.md`

- [ ] **Step 1: Formatter** — Run: `dart format lib test --output=write`; Expected: clean (report file count).
- [ ] **Step 2: Static analysis** — Run: `flutter analyze`; Expected: No issues found.
- [ ] **Step 3: Full test suite** — Run: `flutter test`; Expected: All tests passed; record exact count and per-file breakdown in the log (prior baseline was 79/79 before this phase).
- [ ] **Step 4: Android debug build** — Run: `flutter build apk --debug`; Expected: √ Built; record APK path + size (`build\app\outputs\flutter-apk\app-debug.apk`).
- [ ] **Step 5: Handoff documentation (spec §18, prompt handoff section):**
  - `IMPLEMENTATION_PROGRESS.md`: Phase 4 completed-work list, acceptance checklist with the actual evidence from Steps 1–4, known limitations (no full-DB encryption — evaluation documented; no on-device verification of picker/preview/notification flows — flagged for Phase 5; one-time reminders limitation carried forward).
  - `WORK_LOG.md`: dated entry — decisions (encryption design + key handling rationale, backup format v1 table, file-picker copy behavior verified in android_file_picker source), every command with its actual output, test evidence, known issues.
  - Do NOT claim security certification or legal compliance (spec §14 final paragraph).

---

## Self-Review notes (completed at authoring time)

- **Spec coverage:** §12 → Tasks 3–5 (+Task 4 cleanup); §14 → Task 7 audit + design decisions in Global Constraints/Encryption design; §15 → Tasks 1–2, 6; §16 backup/settings card → Task 6. All prompt verification items map to tests (attach/reopen image+PDF → T5; persistence after restart = files on disk + rows in DB, covered by T3/T4 file assertions and noted as Phase-5 on-device item; delete cleanup → T3/T4; export/restore clean state → T2; wrong password/corrupt safety → T2 Review Focus tests; log inspection → T7; no network → T7 manifest test).
- **Type consistency:** `BackupError` subtypes, `BackupCrypto.{encrypt,decrypt,formatVersionOf}`, `AttachmentFileService` methods, `ClaimActions.attachFile`, `RestoreReport` — defined once (Tasks 1–4) and referenced identically in Tasks 2, 5, 6.
- **Proportion:** plan carries decisions the implementer cannot make alone (crypto parameters, format bytes, error taxonomy, staging order, guard rules); bodies left to signatures + tests.
