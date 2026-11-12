# SDD ledger — plan: docs/superpowers/plans/2026-11-11-phase4-attachments-security-backup.md

Note: workspace is NOT a git repository (verified in Phase 1). Commit steps replaced by WORK_LOG.md entries per spec §18. Executing natively in c:/Users/Majesty/Projects/finaldev with user consent ("execute").

Pre-flight interface scan:
- T2 consumes T1 `BackupCrypto.{encrypt,decrypt,formatVersionOf}` + error types — signatures match plan Task 1 Interfaces block; no conflict.
- T2 codes against `AttachmentFileService` (T3) methods `importFile/fileFor/deleteFile/replaceStoreFrom` — defined in T2's Interfaces block and consumed identically by T3/T4/T6; consistent.
- T4 consumes T3 service + repo; T5 consumes T4 `attachFile`; T6 consumes T2 `BackupService` + T3 service; all signatures cross-checked against plan text — no conflicts found.
- Ruling (setup): skill scripts sdd-workspace/task-start/task-done/review-package are git-based and unusable without a repo; ledger is maintained manually in this file, task completion lines use the same format with test evidence instead of commit ranges (consistent with Phase 2/3 ledgers). Cost if wrong: none — the record survives compaction either way.
## Progress

Task 1: complete (tests: flutter test → 86/86 pass incl. 7 new backup_crypto tests; flutter analyze → No issues found; dart format --set-exit-if-changed → clean)
- Ruling: ByteData.sublistView requires 8-byte alignment — header u16/u32/u64 fields at unaligned offsets use explicit big-endian byte helpers instead. Cost if wrong: none, layout is documented in the file and tests pin it.
- Ruling: pointycastle 4.0.0 deprecates AESFastEngine (side-channel issues) — used AESEngine from block/aes.dart. Cost if wrong: none; same algorithm, non-deprecated path.

Task 2: complete (tests: flutter test → 93/93 pass incl. 7 new backup_service tests covering export-not-plaintext, clean-state restore of claims/history/reminders/attachments, wrong-passphrase fail-closed with live data + files intact and no staging leftovers, flipped-byte rejection, incompatible-version rejection before any mutation, missing-file staged validation abort, atomic swap without duplicate accumulation; flutter analyze → No issues found; dart format --set-exit-if-changed → clean)
- Ruling: export serializes a stored row whose live file is missing/empty as a zero-length entry (archive stays structurally complete); restore rejects it during staged validation. Cost if wrong: none — spec §15 "missing attachments" fails closed on both ends and the test pins it.
- Ruling: host tests that open DBs via the plain sqflite API need `sqflite.databaseFactory = ffi.databaseFactoryFfi` in setUpAll — `sqfliteFfiInit()` only loads the Windows DLL, it does not set the global factory (verified against sqflite_common_ffi 2.4.7 source). Cost if wrong: none; documented pattern from the package README.
- Ruling: `Directory.listSync(recursive: true)` is lazy — deleting while iterating throws once a parent dir is gone; materialize with `.toList()` + per-entry existsSync guard (applied in replaceStoreFrom and test teardowns). Cost if wrong: none.
- Fix (latent bug): AttachmentsRepository.create inserted an explicit id → UNIQUE collision on the 2nd row of any claim; now strips `id` like ClaimsRepository.create. Cost if wrong: none — matches existing project convention, tests pin it.

Task 3: complete (tests: flutter test → 99/99 pass incl. 6 new attachment_file_service tests: import bytes+relative path with source untouched, hostile-name sanitization stays inside store, deleteFile traversal refusal leaves foreign file byte-identical, exact-file delete with sibling intact, store-only resolution + isInsideStore predicate, replaceStoreFrom swap without old-file leaks; flutter analyze → No issues found; dart format --set-exit-if-changed → clean)
- Ruling: interface aligned to plan Task 3 exactly (const ctor + public baseDir + storeDir() + isInsideStore) — superset of what Task 2 consumes. Cost if wrong: none, both test files pin it.
- Ruling: import uniqueness via '<epoch-ms>-<counter>' subdir (top-level mutable counter to dodge prefer_final_fields on a static). Cost if wrong: none; relative_path UNIQUE + tests pin behavior.

Task 4: complete (tests: flutter test → 104/104 pass incl. 5 new claim_actions_attachments tests: attach stores bytes+linked row and returns it, FK-violation insert failure leaves zero files in store, deleteClaim removes only that claim's file with B's file byte-intact + row intact (Review Focus #4), missing source → ArgumentError no partial state, null-service contract; flutter analyze → No issues found; dart format --set-exit-if-changed → clean)
- Ruling: file_picker 13.3.3 is a static API — `FilePicker.pickFiles(type:)`; plan text's `.platform` getter and `withData:` parameter do not exist in 13.x (verified against pub-cache source). Seam omits both. Cost if wrong: none — analyzer would have failed on the nonexistent members; tests pin behavior through the seam interface only.
- Ruling: ClaimActions constructor keeps positional `(db, scheduler)` and adds optional named `files` (default null) → all existing constructions stay valid; attachFile throws StateError without a service, deleteClaim skips file cleanup. Cost if wrong: none — both behaviors are pinned by tests.

