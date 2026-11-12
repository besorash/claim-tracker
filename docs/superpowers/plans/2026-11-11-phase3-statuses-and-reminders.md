# Phase 3 — Status Workflow, History & Local Reminders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the Phase 1 status/reminder/notification foundation into real user flows — atomic status changes with visible history, per-claim one-time reminders with permission handling, close/delete that cancel scheduled notifications, and notification-tap routing to the correct claim.

**Architecture:** A thin `ClaimActions` orchestration class (repos + an injected `ReminderScheduler`) owns every mutation flow so screens stay router-free and testable — same injection pattern as Phase 2 (`onMetricTapped`, `onSaved`). `NotificationService` already implements the scheduler interface; widget tests inject a fake that records calls, so no method channels are touched on host. Recurring reminders are deliberately NOT shipped (spec §10 fallback clause: one-time first, document limitation).

**Tech Stack:** Flutter 3.47 / Dart 3.13, existing packages only — **no new dependencies**. sqflite + sqflite_common_ffi for host tests; flutter_local_notifications 23.0.1 (already integrated in Phase 1).

**Spec:** `MASTER_PROJECT_SPEC.md` §8–§11 (authoritative); phase scope in `PROMPT_3_STATUSES_AND_REMINDERS.md`.

## Global Constraints

- Arabic is the default language; RTL everywhere; all UI text via `lib/core/l10n/app_strings.dart` (`S.*`) — no literal Arabic in widget code. Most needed strings already exist (status flow, reminders, permission dialogs).
- Both Light and Dark themes must render every new dialog/section without low-contrast text (spec §3.2); theme tokens only.
- Status definitions come ONLY from `ClaimStatus.all` / `ClaimStatus.byKey` — no literal status strings in UI code (spec §8).
- Closed = status key `closed` ONLY; `compensated` stays open (spec §5, already enforced by repositories).
- Timestamps stored UTC (`*_utc_ms`), displayed via `TimeUtils` (Asia/Riyadh) — spec §10.
- Stable notification IDs: one reminder per claim, `notificationId == claimId` (reschedule/cancel never collide; survives row replacement).
- Lock-screen text stays generic (`AppConstants.genericReminderTitle/Body`) — no customer data (spec §14).
- No non-functional buttons (spec §3.3); recurring-interval controls are FORBIDDEN this phase (documented limitation, not a stub).
- Widget-test harness rules from Phase 2 ledger: ALL FFI I/O inside ONE `tester.runAsync` block; bounded settle (`delay + pump(16ms)` loop) instead of `pumpAndSettle`; nav taps scoped to `NavigationBar`; Arabic DatePicker OK label is `حسنًا`.

## Review Focus

1. **Close/delete a claim with a pending reminder** — the OS-side alarm must be cancelled, not just the DB row removed (a stale notification firing later is the worst failure mode). Pinned by Task 1 tests asserting `scheduler.cancelReminder` was called for every removed row, and that a throwing scheduler does not abort the close/delete.
2. **Rescheduling the same claim twice** — exactly one reminder row must exist and both schedules must reuse the SAME stable notification id (duplicates after reschedule are spec §10's explicit failure). Pinned by Task 4 test: two saves → `reminders` count == 1, fake scheduler saw identical `notificationId`.
3. **Status change with a new follow-up** — prior history rows must survive and the new row must be appended (spec §9 "never overwrite or discard"). Pinned by Task 2 + Task 3 tests: history length grows, oldest entry unchanged, newest first in UI.
4. **Permission denied when saving a reminder** — the reminder must still persist in-app (row + claim follow-up date) with scheduling skipped and an Arabic explanation of how to enable notifications shown (spec §10). Pinned by Task 4 test with fake scheduler reporting denied.
5. **Notification tap routing edge cases** — tapping after cold start routes into the live shell; routing to a deleted/unknown claim must land on the not-found state, never crash. Pinned by Task 5 tests (hook call with seeded id → details visible; hook call with unknown id → `S.claimNotFound` visible).

---

### Task 1: ReminderScheduler seam + ClaimActions (close/delete/status orchestration)

**Files:**
- Create: `lib/core/notifications/reminder_scheduler.dart`
- Modify: `lib/core/notifications/notification_service.dart` (class declaration line only — add `implements ReminderScheduler`)
- Create: `lib/features/claims/claim_actions.dart`
- Test: `test/features/claim_actions_test.dart`

**Interfaces:**
- Consumes: `StatusHistoryRepository.changeStatus({claimId, newStatusKey, changedAtUtc, note})`, `RemindersRepository.replaceForClaim/disableAllForClaim/removeAllForClaim`, `ClaimsRepository.delete(id)`, `Reminder`, `NotificationPermissionState`.
- Produces (exact signatures — later tasks depend on these):

```dart
// lib/core/notifications/reminder_scheduler.dart
abstract class ReminderScheduler {
  Future<NotificationPermissionState> requestNotificationsPermission();
  Future<bool> areNotificationsEnabled();
  Future<void> scheduleReminder(Reminder reminder);
  Future<void> cancelReminder(int notificationId);
}

// lib/features/claims/claim_actions.dart
sealed class FollowUpChange { const FollowUpChange(); }
class KeepFollowUp extends FollowUpChange { const KeepFollowUp(); }
class SetFollowUp extends FollowUpChange { const SetFollowUp(this.atUtc); final DateTime atUtc; }
class ClearFollowUp extends FollowUpChange { const ClearFollowUp(); }

class ClaimActions {
  const ClaimActions(this._db, this.scheduler);
  final AppDatabase _db;
  final ReminderScheduler scheduler;

  /// Atomic status+history write (spec §9), then applies [followUp]:
  /// Keep = no reminder change; Set(atUtc) = saveReminder(claimId, atUtc);
  /// Clear = clearFollowUp(claimId).
  Future<void> changeStatus(int claimId, String newStatusKey, {String? note, required FollowUpChange followUp});

  /// Replaces the claim's single reminder (enabled=1, notificationId == claimId),
  /// sets claims.next_follow_up_utc_ms = fireAtUtc, then schedules. Returns stored row.
  Future<Reminder> saveReminder({required int claimId, required DateTime fireAtUtc});

  /// Cancels the OS alarm + disables the DB row; keeps the follow-up date visible in-app.
  Future<void> disableReminder(int claimId);

  /// Cancels the OS alarm, removes the reminder row, nulls claims.next_follow_up_utc_ms.
  Future<void> clearFollowUp(int claimId);

  /// changeStatus(closed) + cancel & remove all reminders (spec §10).
  Future<void> closeClaim(int claimId);

  /// Cancel & remove all reminders FIRST, then ClaimsRepository.delete (FK cascade removes history).
  Future<void> deleteClaim(int claimId);
}
```

- [ ] **Step 1: Write the failing tests** in `test/features/claim_actions_test.dart`.
  Setup mirrors Phase 2 FFI pattern: `ffi.sqfliteFfiInit()` + `ffi.databaseFactory = ffi.databaseFactoryFfi;` in setUpAll, `TimeUtils.ensureInitialized()`, per-test in-memory DB via `databaseFactoryFfi.openDatabase(ffi.inMemoryDatabasePath)` + `PRAGMA foreign_keys = ON` + `AppDatabase.migrate`. Define a recording fake:
  ```dart
  class FakeScheduler implements ReminderScheduler {
    final List<int> cancelled = [];
    final List<Reminder> scheduled = [];
    bool enabled = true;
    @override Future<void> cancelReminder(int id) async => cancelled.add(id);
    @override Future<void> scheduleReminder(Reminder r) async => scheduled.add(r);
    @override Future<bool> areNotificationsEnabled() async => enabled;
    @override Future<NotificationPermissionState> requestNotificationsPermission() async => NotificationPermissionState.granted;
  }
  ```
  Tests (all FFI I/O inside one `tester.runAsync`-free plain `test()` — these are pure Dart/FFI, no widget pumping needed):
  - `closeClaim cancels the pending reminder and records history`: seed claim (`ClaimsRepository.create`, status `new`) + reminder row via `RemindersRepository.replaceForClaim(claimId: id, next: Reminder(id:0, claimId:id, fireAtUtcMs: now+1d, notificationId: id, enabled:true, ...))`. Call `actions.closeClaim(id)`. Assert: `db.claimById(id)` statusKey == `closed`; `StatusHistoryRepository(db).listForClaim(id)` has 1 row with previousStatusKey `new`, newStatusKey `closed`; reminders table empty (query via `RemindersRepository` — add a read if needed, or assert through `allEnabled()` being empty AND `enabledAfter(now-1d)` empty); `fake.cancelled` contains `id`.
  - `closeClaim survives a throwing scheduler`: fake whose `cancelReminder` throws; close still completes, claim is closed, reminders removed (wrap cancel in try/catch per interface doc).
  - `deleteClaim cancels reminders before deleting the row`: seed claim + reminder; call `actions.deleteClaim(id)`; assert `db.claimById(id)` null, history empty (cascade), `fake.cancelled` contains `id`.
  - `changeStatus with SetFollowUp persists status AND schedules the follow-up`: seed claim; call `changeStatus(id, 'submitted', note: 'ملاحظة', followUp: SetFollowUp(now+2d))`; assert DB statusKey == `submitted`, history row has note, `claims.next_follow_up_utc_ms` set (read via `db.claimById`), `fake.scheduled.single.notificationId == id`.
  - `changeStatus with KeepFollowUp does not touch reminders`: seed claim + reminder; change with `KeepFollowUp`; assert reminder row still present and enabled, `fake.cancelled` empty.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/claim_actions_test.dart`
Expected: FAIL — `reminder_scheduler.dart` / `claim_actions.dart` do not exist (compile error).

- [ ] **Step 3: Implement.**
  - `ReminderScheduler`: the four methods above, doc-commented as "injection seam for widget tests; production implementation is `NotificationService`".
  - `notification_service.dart`: change class declaration to `class NotificationService implements ReminderScheduler {` — all four members already exist with matching signatures (verify no signature drift; add `@override` annotations).
  - `ClaimActions`: compose the existing repositories. `saveReminder` builds `Reminder(id: 0, claimId:, fireAtUtcMs: fireAtUtc.toUtc(), notificationId: claimId, repeatIntervalHours: null, enabled: true, createdAt/updatedAt now)` → `replaceForClaim` → update `claims.next_follow_up_utc_ms` (direct `_db.rawDb.update`) → `scheduler.scheduleReminder(stored)`. Cancellation loops wrap each `cancelReminder` in try/catch (Review Focus #1). `clearFollowUp`: cancel + `removeAllForClaim` + null the claim's follow-up.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/claim_actions_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Record in WORK_LOG.md / ledger** (no git repo — commit step replaced per project convention).

---

### Task 2: Status-change dialog on the claim details screen

**Files:**
- Modify: `lib/features/claims/claim_details_screen.dart` (add action button + `_changeStatus()` flow)
- Test: extend `test/features/claim_details_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 `ClaimActions`, `FollowUpChange`; `ClaimStatus.all` (dropdown source); existing strings `S.changeStatusTitle`, `S.statusNoteHint`, `S.setNextFollowUp`, `S.keepExistingFollowUp`, `S.save`, `S.cancel`.
- Produces: `ClaimDetailsScreen({required AppDatabase db, required int claimId, ReminderScheduler? scheduler})` — new optional param (default `NotificationService.instance`) so tests inject a fake; screen builds `ClaimActions(db, scheduler)` lazily. A bottom-bar button labeled `S.changeStatusTitle`-adjacent: use label **`تغيير الحالة`** → add string `static const String changeStatus = 'تغيير الحالة';` to `S` (the existing `changeStatusTitle` is the dialog title).

Dialog layout (eager, single screen): status `DropdownButton<String>` over `ClaimStatus.all` (value = key, label = Arabic name; initial value = current claim's status), optional note `TextField`, follow-up radio group — `S.keepExistingFollowUp` / `S.setNextFollowUp` (+ tappable date-time row using the same `showDatePicker(locale: ar)` + `showTimePicker` pattern as the form screen, OK label `حسنًا`) / clear option (reuse `S.cancel`-style wording via a new string `clearFollowUp = 'إلغاء الموعد'`). Confirm button calls `actions.changeStatus(...)` with the matching `FollowUpChange`, then refreshes `_load()`.

- [ ] **Step 1: Write the failing widget tests** in `test/features/claim_details_screen_test.dart` (extend existing file; reuse its FFI harness + push-based pattern from Phase 2 Task 5).
  - `status change persists atomically with history and a new follow-up`: seed claim status `new`; open details (push harness); tap the change-status button → dialog visible (`S.changeStatusTitle`); select `ClaimStatus.submitted.key` label; type note 'تم التقديم'; choose set-follow-up + pick date/time (tap row, settle dialog, tap `حسنًا` twice for date then time); tap confirm. Assert: DB claim statusKey == submitted key; history length 1 with note preserved; `next_follow_up_utc_ms` non-null; screen shows the new `StatusChip`.
  - `status change keeps existing follow-up when chosen`: seed claim with follow-up + reminder row; open dialog; choose keep; confirm. Assert: follow-up unchanged, reminder still enabled, history grew by 1.

- [ ] **Step 2: Run to verify failure** — expected FAIL (button/dialog missing).

- [ ] **Step 3: Implement.** Add `scheduler` param + lazy `ClaimActions`; `_changeStatus()` opens the dialog; on confirm await actions then `_load()`. Keep the screen's existing eager layout and bottom bar (add a third button or move Delete to overflow — keep all three visible, wrap in `Wrap` if cramped).

- [ ] **Step 4: Run to verify pass** — expected PASS.

- [ ] **Step 5: Record in WORK_LOG.md / ledger.**

---

### Task 3: Status history section on the claim details screen

**Files:**
- Modify: `lib/features/claims/claim_details_screen.dart` (new `_section(S.statusHistoryLabel, ...)` + load history in `_load()`)
- Test: extend `test/features/claim_details_screen_test.dart`

**Interfaces:**
- Consumes: `StatusHistoryRepository.listForClaim(claimId)` (newest first), `ClaimStatus.byKey(key).labelAr`, `TimeUtils.formatDateTime`, existing string `S.statusHistoryLabel`.
- Produces: a history section rendered newest-first; each row shows new-status label, timestamp, optional note; the FIRST row's status must match the claim's current status and be visually distinguished (e.g., filled chip vs. outlined text for older rows).

- [ ] **Step 1: Write the failing widget test.**
  Seed a claim, then apply two changes via `StatusHistoryRepository.changeStatus` (`new → submitted`, note 'أولى'; `submitted → approved`). Open details. Assert: section title `S.statusHistoryLabel` visible; both Arabic status labels present in order (approved row appears before submitted row — assert index positions); the note 'أولى' is visible; current-status chip label matches `ClaimStatus.byKey(claim.statusKey).labelAr`.

- [ ] **Step 2: Run to verify failure** — expected FAIL.

- [ ] **Step 3: Implement.** Load history alongside the claim in `_load()` (null-safe when empty → render a muted "no changes yet" line using an existing or new string `historyEmpty = 'لا توجد تغييرات مسجلة بعد.'`).

- [ ] **Step 4: Run to verify pass** — expected PASS.

- [ ] **Step 5: Record in WORK_LOG.md / ledger.**

---

### Task 4: Reminder dialog (set/reschedule/disable) + permission flow

**Files:**
- Modify: `lib/features/claims/claim_details_screen.dart` (reminder section + `_saveReminder()` / `_disableReminder()`)
- Modify: `lib/core/database/reminders_repository.dart` (add one read method — see Interfaces)
- Test: extend `test/features/claim_details_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 `ClaimActions.saveReminder/disableReminder`; Task 2's injected `scheduler`.
- Produces:
```dart
// added to RemindersRepository (read-only, for the details screen state line)
Future<Reminder?> latestForClaim(int claimId); // row with max(id) where claim_id = ?
```
  Details-screen reminder section shows current state from `latestForClaim` + `claim.nextFollowUpUtcMs`: enabled → `S.reminderEnabled` + formatted fire time; disabled/absent → `S.reminderDisabled`. Buttons: **set/reschedule** (date-time picker dialog, same pattern as Task 2) and **disable** (`S.cancel`-labeled? NO — add string `reminderDisable = 'إيقاف التذكير'`).

Permission flow inside `_saveReminder(fireAtUtc)` (spec §10): if `await scheduler.areNotificationsEnabled()` is false → show explanation dialog (`S.notificationsPermissionTitle/Body`) with allow button → `requestNotificationsPermission()`; still denied → show `S.notificationsDeniedTitle/Body` info. In ALL cases the reminder row + claim follow-up date are persisted (in-app state must not depend on OS permission); scheduling only happens when granted.

- [ ] **Step 1: Write the failing widget tests.**
  - `saving a reminder persists it and schedules with the stable id`: fake scheduler enabled; open details → tap set-reminder → pick date/time (`حسنًا` ×2) → confirm. Assert: `latestForClaim(id)` non-null, `enabled == true`, `notificationId == claimId`; `fake.scheduled.single.notificationId == claimId`; section now shows `S.reminderEnabled`.
  - `rescheduling reuses the same notification id and keeps one row`: save twice with different dates. Assert: reminders count for claim == 1 (query via repo), both fake-schedule calls used `notificationId == claimId` (Review Focus #2).
  - `disabling cancels the alarm but keeps the date visible`: after a save, tap disable → assert `fake.cancelled` contains `id`, row `enabled == false`, section shows `S.reminderDisabled`, claim's follow-up date still displayed.
  - `denied permission still persists the reminder and explains in Arabic`: fake with `areNotificationsEnabled() => false`, request returns denied; save a reminder → assert DB row persisted + enabled, `fake.scheduled` EMPTY, and `S.notificationsDeniedBody` text was shown (Review Focus #4).

- [ ] **Step 2: Run to verify failure** — expected FAIL.

- [ ] **Step 3: Implement.** Add `latestForClaim`; reminder section + dialog; permission flow as specified above.

- [ ] **Step 4: Run to verify pass** — expected PASS (4 tests).

- [ ] **Step 5: Record in WORK_LOG.md / ledger.**

---

### Task 5: Notification-tap routing into the live shell

**Files:**
- Modify: `lib/app/home_shell.dart` (static hook + initState/dispose wiring)
- Modify: `lib/main.dart` (assign `NotificationService.onClaimTapped`)
- Test: extend `test/widget_test.dart`

**Interfaces:**
- Consumes: existing static `NotificationService.onClaimTapped` (`void Function(int claimId)?`, invoked by the plugin's response handler with the parsed payload id).
- Produces:
```dart
// HomeShell — set by its State while mounted, cleared on dispose:
static void Function(int claimId)? openClaimFromNotification;

// main.dart, before runApp (after NotificationService.instance.init()):
NotificationService.onClaimTapped = (int claimId) => HomeShell.openClaimFromNotification?.call(claimId);
```
  `_HomeShellState.initState` assigns `HomeShell.openClaimFromNotification = _openClaim;`; `dispose` clears it only if still identical.

- [ ] **Step 1: Write the failing widget tests** in `test/widget_test.dart` (reuse existing harness + FFI setup).
  - `notification tap opens the correct claim details`: seed one claim; pump shell; settle dashboard; call `HomeShell.openClaimFromNotification!(claimId)` inside runAsync; settle until `find.byType(ClaimDetailsScreen)` is non-empty; assert the seeded claim number text is visible. Reset the static in tearDown (`HomeShell.openClaimFromNotification = null;`).
  - `routing to an unknown claim lands on the not-found state`: call hook with id 999999; settle; assert `S.claimNotFound` visible and no exception (Review Focus #5).

- [ ] **Step 2: Run to verify failure** — expected FAIL (static is null → no-op, details never appears).

- [ ] **Step 3: Implement.** Wire as specified. Note: `_openClaim` already bumps `_gen` on return — reuse it unchanged.

- [ ] **Step 4: Run the full suite** — `flutter analyze && dart format lib test --output=write && flutter test` → all green (expect ~75 tests).

- [ ] **Step 5: Build debug APK + record handoff.**
  - `flutter build apk --debug` → success; record path + size in WORK_LOG.md.
  - Ledger entry with rulings: one-time-only reminders (spec §10 fallback clause — recurring control deliberately not shipped, `repeatIntervalHours` stays null from UI); `notificationId == claimId` stability ruling; permission-denied still persists in-app state; scheduler-injection seam rationale (no method channels on host).
  - `IMPLEMENTATION_PROGRESS.md`: Phase 3 complete + acceptance checklist + next action = read `PROMPT_4_ATTACHMENTS_SECURITY_BACKUP.md`.
  - WORK_LOG entry: commands + actual results, platform limitations honestly stated — **reboot reconciliation and real notification delivery were NOT tested on host** (no device/emulator); they rely on flutter_local_notifications' boot receiver + the existing startup reconcile in `main.dart`; flag both as Phase 5 on-device verification items.

---

## Self-Review Notes (completed at plan time)

1. **Spec coverage:** §8 statuses → centralized, used by Task 2 dropdown; §9 atomic history + optional follow-up + display → Tasks 1–3; §10 reminders/permissions/channels/stable ids/reschedule/cancel-on-close-delete/reconcile/timezone/duplicates/routing → Tasks 1, 4, 5 (reconcile already in `main.dart` from Phase 1); §11 actions (change status, set/edit/disable reminder, close claim) → Tasks 2–4. Recurrence: explicitly deferred per spec's own fallback clause — documented, not stubbed.
2. **Step scan:** every step is one action with a checkable result; no "handle edge cases" lines.
3. **Type consistency:** `ReminderScheduler` signatures match the four existing `NotificationService` members exactly (verified against source); `ClaimActions` method names used identically in Tasks 2–4; `FollowUpChange` variants named once and reused.
4. **Review Focus:** all five lines pinned to named tests in their owning tasks (1→Task 1, 2→Task 4, 3→Tasks 2+3, 4→Task 4, 5→Task 5).
5. **Proportion:** plan is shorter than the spec sections it implements; bodies omitted where signatures + tests determine behavior.
