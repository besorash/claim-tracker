# Phase 2 — Core UI, Dashboard & Claim Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build the Phase 2 screens — dashboard, claims list with search/filters, add/edit claim forms, claim details, and settings — on top of the verified Phase 1 foundation (SQLite repositories, models, theme tokens, Arabic RTL shell).

**Architecture:** Feature folders under `lib/features/{dashboard,claims,settings}` per spec §13. A thin `DashboardService` computes metrics from `ClaimsRepository` queries (no hardcoded values). Screens are plain Flutter widgets using the existing `AppTheme`, `S` strings, and `StatusChip`; no new state-management package (YAGNI — a single-user local app with repository-backed screens).

**Tech Stack:** Flutter 3.47 / Dart 3.13, sqflite (+sqflite_common_ffi for tests), existing Phase 1 packages only — **no new dependencies**.

**Spec:** `MASTER_PROJECT_SPEC.md` §3–§8, §11, §16 (authoritative); phase scope in `PROMPT_2_CORE_UI_AND_CLAIMS.md`.

## Global Constraints

- Arabic is the default language; RTL everywhere; all UI text via `lib/core/l10n/app_strings.dart` (`S.*`) — no literal Arabic in widget code.
- Palette: navy `#101D35`, deep blue `#173D5C`, teal `#19A99A`, light bg `#F3F5F8`; semantic tokens only, never raw colors in widgets (spec §3.1).
- Every dashboard metric derived from SQLite; tapping a metric navigates to the correctly filtered claims list (spec §5).
- Closed = status key `closed` (مغلقة) ONLY — `compensated` stays open (spec §5, already enforced by `ClaimsRepository`).
- Search covers: claim number, customer name, mobile, accident number, both insurers, insurer ref; forgiving of whitespace (spec §6).
- Required fields per spec §7.1–§7.3: customerName, customerMobile, accidentDateUtcMs, claimNumber, customerInsuranceCompany, submittedToInsuranceCompany, submissionDateUtcMs. Validation messages in Arabic (`S.requiredField` etc.); preserve user input on validation failure.
- Claim number is NOT unique (spec §7) — no uniqueness validation.
- No contact history/calls/SMS/email/WhatsApp/cloud features (prompt boundary).
- Both Light and Dark themes must be checked for every screen; no low-contrast text (spec §3.2).
- Tests run on host via `sqflite_common_ffi` in-memory DB (`PRAGMA foreign_keys = ON` required per connection — see existing tests).

## Review Focus

1. **Validation failure preserves input** — user fixes one field, all other typed values must remain (spec §7); pinned by Task 4 widget test.
2. **Dashboard metric tap → correct filter** — tapping "متأخرة" opens the list with `filterOverdue` active and only overdue claims; pinned by Task 1 + Task 3 tests.
3. **Closed vs open counting** — a claim in `compensated` must appear under Open, not Closed (spec §5); pinned by Task 1 test.
4. **Mixed Arabic/English search input** — e.g. query "clm-200" and "محمد" both work; whitespace trimmed; no crash on empty/pure-space queries; pinned by existing repository tests + Task 3 widget test.
5. **Persistence across restart** — created claim survives a fresh `AppDatabase.open()` (new connection); pinned by Task 4 integration-style test using two separate in-memory DBs is NOT possible with FFI, so instead: create → close DB → reopen same file path via `sqfliteFfiInit` + `openDatabase(path)` and assert the row exists.

## File Structure

- Create: `lib/features/dashboard/dashboard_service.dart` — metric computation from repository
- Create: `lib/features/dashboard/dashboard_screen.dart` — metrics grid + needs-attention list
- Create: `lib/features/claims/claim_card.dart` — balanced card (spec §6)
- Create: `lib/features/claims/claims_list_screen.dart` — search, filter chips, list, empty states
- Create: `lib/features/claims/claim_form_model.dart` — form state + Arabic validation (pure Dart, unit-testable)
- Create: `lib/features/claims/claim_form_screen.dart` — add/edit form UI using the model
- Create: `lib/features/claims/claim_details_screen.dart` — full details + actions (edit/delete/close; status & reminder flows are Phase 3 placeholders that navigate to a "قريبًا" state is FORBIDDEN — instead show only Edit/Delete now, per prompt boundary)
- Create: `lib/features/settings/settings_screen.dart` — theme selection (persisted), notifications info, app version
- Modify: `lib/app/home_shell.dart` — wire real screens into the four destinations + prominent Add Claim action
- Test: `test/features/dashboard_service_test.dart`, `test/features/claim_form_model_test.dart`, `test/features/claims_list_screen_test.dart`, `test/features/claim_form_screen_test.dart`, `test/features/settings_screen_test.dart`

---

### Task 1: DashboardService (metrics from SQLite)

**Files:**
- Create: `lib/features/dashboard/dashboard_service.dart`
- Test: `test/features/dashboard_service_test.dart`

**Interfaces:**
- Consumes: `ClaimsRepository.all()/open()/closed()/overdue(nowUtc)/dueBetween(start,end)`; `TimeUtils.riyadhDayRange(nowUtc)`.
- Produces:
  - `class DashboardMetrics { final int total, open, closed, dueToday, overdue; }` (all non-null ints)
  - `class NeedsAttentionItem { final Claim claim; final bool isOverdue; }`
  - `Future<DashboardMetrics> metrics()` — counts from repository queries.
  - `Future<List<NeedsAttentionItem>> needsAttention({int limit = 5})` — overdue first, then due-today, then recently updated (by `updatedAtUtcMs` desc), capped at [limit].

- [x] **Step 1: Write the failing test** in `test/features/dashboard_service_test.dart`.
  Setup mirrors `test/database/repositories_test.dart`: FFI init, open in-memory DB, `PRAGMA foreign_keys = ON`, migrate, wrap with `AppDatabase.fromExisting`. Seed via `ClaimsRepository.create` (id auto-assigned): one claim status `new` no follow-up; one `compensated`; one `closed`; one `new` with follow-up yesterday (overdue); one `new` with follow-up now+2h (due today).
  Assertions:
  - `metrics()` → total 5, open 4, closed 1 (the compensated claim counts OPEN — spec §5), dueToday 1, overdue 1.
  - `needsAttention(limit: 3)` → first item is the overdue claim (`isOverdue == true`), second is the due-today claim; length ≤ 3.
  - Empty DB case (fresh in-memory DB): all metrics 0 and `needsAttention()` empty — this pins "no hardcoded values".

- [x] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/dashboard_service_test.dart`
Expected: FAIL — `dashboard_service.dart` does not exist (compile error).

- [x] **Step 3: Implement `DashboardService` in `lib/features/dashboard/dashboard_service.dart`**

Constructor takes `ClaimsRepository`. `metrics()` calls the five repository queries and returns their lengths. `needsAttention()`: compute Riyadh day range via `TimeUtils.riyadhDayRange(DateTime.now().toUtc())`; take `overdue(now)` (flag overdue) + `dueBetween(start,end)` (not overdue), sort overdue-first then by follow-up asc, append remaining from `all()` sorted by `updatedAtUtcMs` desc until [limit]. No other logic.

- [x] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/dashboard_service_test.dart`
Expected: PASS (3 tests).

- [x] **Step 5: Commit** — not applicable (workspace is not a git repository; record in WORK_LOG.md instead).

---

### Task 2: DashboardScreen UI

**Files:**
- Create: `lib/features/dashboard/dashboard_screen.dart`
- Modify: `lib/core/l10n/app_strings.dart` (add missing strings only if needed — most exist already)
- Test: extend `test/widget_test.dart` or create `test/features/dashboard_screen_test.dart`

**Interfaces:**
- Consumes: `DashboardService`, `S.dash*` strings, `AppTheme.muted(context)`, `StatusChip`.
- Produces: `class DashboardScreen extends StatefulWidget { const DashboardScreen({super.key, required this.service}); }` — self-contained; takes the service (testable with a seeded FFI DB).

- [x] **Step 1: Write the failing widget test** in `test/features/dashboard_screen_test.dart`.
  Seed an FFI in-memory DB exactly like Task 1's setup (5 claims as above), build `MaterialApp(locale ar, theme AppTheme.light(), darkTheme AppTheme.dark(), home DashboardScreen(service))` inside a `Directionality(rtl)` wrapper.
  Assertions:
  - All five metric labels visible (`S.dashTotalClaims`, `dashOpenClaims`, `dashClosedClaims`, `dashDueToday`, `dashOverdue`).
  - Metric values rendered as Arabic-Indic digits are NOT required — assert the numeric strings `'5'`/`'4'`/`'1'` appear (use `find.textContaining('5')` style or exact `find.text('5')` on the value Text widgets).
  - Tapping the overdue metric tile navigates: wrap in a `NavigatorObserver`-free approach — instead assert the tap handler by pumping and checking no exception + that a route was pushed (use `tester.state<NavigatorState>(find.byType(Navigator)).entries.length == 2`). The screen must push `ClaimsListScreen(initialFilter: ClaimsFilter.overdue)` (Task 3) — for this task, stub navigation with a simple `Navigator.push` to a placeholder-free real screen only if Task 3 exists; otherwise the test asserts the tile is tappable (`find.byKey(Key('metric-overdue'))`) and records the intended route in code. **Decision: implement tiles as `InkWell`s that call a constructor-provided `onMetricTapped(ClaimsFilter filter)` callback (default pushes ClaimsListScreen); the widget test injects a recorder to assert `ClaimsFilter.overdue` was requested.** This keeps navigation testable without a live router.
  - Empty state: fresh empty DB → `S.dashEmpty` visible and no metric tiles crash on zero values.

- [x] **Step 2: Run test to verify it fails** — `flutter test test/features/dashboard_screen_test.dart`, expected FAIL (file missing).

- [x] **Step 3: Implement the screen.**
  Layout: `SafeArea` + `SingleChildScrollView`; header row with app title; a 2-column grid of metric tiles (`GridView.count(crossAxisCount: 2, childAspectRatio ~1.6)`); each tile = Card with icon (line icons), value (titleLarge bold), label (bodySmall muted). "تحتاج إلى انتباهك" section: list of up to 5 `NeedsAttentionItem`s rendered as compact rows (claim number + customer name + overdue/due-today chip via existing `TimeUtils.followUpLabel`); each row tappable → details screen (Task 6) — for now navigate via the same callback pattern with a claim id. Empty DB: centered icon + `S.dashEmpty`.
  Colors only from theme tokens; icons `Icons.dashboard_outlined`, `folder_open_outlined`, `check_circle_outline`, `event_available`, `warning_amber` (line style per spec §3.3).

- [x] **Step 4: Run test to verify it passes** — expected PASS.

- [x] **Step 5: Record in WORK_LOG.md** (no git repo).

---

### Task 3: Claims list screen + balanced card + search/filters

**Files:**
- Create: `lib/features/claims/claim_card.dart`
- Create: `lib/features/claims/claims_list_screen.dart`
- Test: `test/features/claims_list_screen_test.dart`

**Interfaces:**
- Consumes: `ClaimsRepository.search/all/open/closed/needsFollowUp/overdue/dueBetween/sortDefault`; `StatusChip`; `TimeUtils.formatDate/followUpLabel`; `S.*`.
- Produces:
  - `enum ClaimsFilter { all, open, followUp, overdue, closed }` (in `claims_list_screen.dart`) with `String get labelAr` mapping to the existing `S.filter*` strings.
  - `class ClaimCard extends StatelessWidget { const ClaimCard({super.key, required this.claim}); }` — shows exactly: claim number, customer name, submitted-to insurer, current status chip, next follow-up (if any), and an overdue/due-today indicator when applicable (spec §6). Nothing else.
  - `class ClaimsListScreen extends StatefulWidget { const ClaimsListScreen({super.key, required this.repo, this.initialFilter = ClaimsFilter.all}); }` — search field + filter chips + list; empty state `S.claimsEmpty`.

- [x] **Step 1: Write the failing widget test** in `test/features/claims_list_screen_test.dart`.
  Seed FFI DB (same pattern as Task 1) with: claim A status `new` follow-up yesterday (overdue), claim B status `closed`, claim C status `compensated` no follow-up, claim D customer name "محمد العتيبي" mobile "0551234567".
  Assertions:
  - Default (`all`): all four cards visible; card A shows the overdue indicator (assert a widget with key `Key('card-overdue-indicator')` exists on that card only).
  - Tap filter chip `S.filterClosed` → exactly one card (claim B) remains.
  - Tap `S.filterOpen` → three cards (A, C, D — compensated counts open per spec §5).
  - Type "محمد" in the search field → only claim D; type "0551234567" → only claim D; type "   " (spaces) → all four (forgiving trim); type "clm-200" style partial of a seeded claim number → matches.
  - Card content: for claim A assert `S.claimNumberLabel` value, customer name, insurer text, status chip label visible — and that the card does NOT contain `S.notesLabel` (balanced subset only).

- [x] **Step 2: Run test to verify it fails** — expected FAIL (files missing).

- [x] **Step 3: Implement.**
  `ClaimsListScreen`: state holds `query`, `filter`; a debounced (or immediate) rebuild calls the matching repository method (`all`/`open`/`closed`/`needsFollowUp`/`overdue(now)`; for `followUp` use `needsFollowUp()`). Search: when query non-empty, call `repo.search(query)` and then apply the filter in-memory by re-checking each claim's status/follow-up against the active filter (keeps one code path). Filter chips: horizontal `SingleChildScrollView` of selectable chips bound to `ClaimsFilter`. List: `ListView.separated` of `ClaimCard`s inside a `RefreshIndicator`-free simple scroll (no pull-to-refresh needed for local data — keep it simple per spec §3.3 "avoid clutter"). Empty state: centered icon + `S.claimsEmpty`.
  `ClaimCard`: Card with Row layout — leading column (claim number bold, customer name), trailing column (insurer small muted, status chip); bottom row: follow-up label via `TimeUtils.followUpLabel` or a colored overdue/due-today indicator (`warning_amber` icon + text) when applicable. Keys: wrap the card in `Key('card-${claim.id}')`; overdue indicator gets `Key('card-overdue-indicator')`.

- [x] **Step 4: Run test to verify it passes** — expected PASS (6+ assertions).

- [x] **Step 5: Record in WORK_LOG.md.**

---

### Task 4: Claim form model + add/edit screens with Arabic validation

**Files:**
- Create: `lib/features/claims/claim_form_model.dart`
- Create: `lib/features/claims/claim_form_screen.dart`
- Test: `test/features/claim_form_model_test.dart`, `test/features/claim_form_screen_test.dart`

**Interfaces:**
- Consumes: `Claim` model; `S.requiredField/S.invalidNumber/S.invalidDate`; `TimeUtils`.
- Produces:
  - `class ClaimFormModel { ... }` — pure Dart, no Flutter imports. Fields mirror the spec §7 required/optional set as editable strings + `DateTime?` for dates. Methods:
    - `String? validateCustomerName()` / `validateMobile()` / `validateClaimNumber()` / `validateCustomerInsurer()` / `validateSubmittedToInsurer()` — return `S.requiredField` when blank (after trim), else null. Mobile additionally rejects non-digit content after stripping spaces/leading +966/0 (return `S.invalidNumber`).
    - `bool get isValid` — all required validators pass AND both dates set.
    - `Claim toClaim({required int id, required DateTime createdAtUtcMs})` / `Claim buildNew(DateTime nowUtc)` and `Claim applyTo(Claim existing, DateTime nowUtc)` (bumps `updatedAtUtcMs`, preserves `id/createdAt`).
  - `class ClaimFormScreen extends StatefulWidget { const ClaimFormScreen({super.key, this.claim}); }` — `claim == null` → add mode; else edit mode. On save: calls injected `onSaved(Claim claim)` callback (screen does NOT touch the repository directly — keeps it testable and lets the shell wire persistence).

- [x] **Step 1: Write failing unit tests** in `test/features/claim_form_model_test.dart`.
  - All required fields blank → each validator returns `S.requiredField`; `isValid` false.
  - Fill all required (name "خالد", mobile "0559876543", claimNumber "CLM-1", both insurers, accidentDate + submissionDate set) → all validators null; `isValid` true.
  - Mobile "abc" → `S.invalidNumber`; mobile "+966 55 987 6543" → valid (normalization); mobile "0551234" (too short, <9 digits after normalization) → `S.invalidNumber`.
  - Whitespace-only name ("   ") → still required.
  - `buildNew`/`applyTo`: assert `updatedAtUtcMs` bumped on edit and `id` preserved; new claim gets provided id + createdAt.

- [x] **Step 2: Run to verify failure** — expected FAIL (file missing).

- [x] **Step 3: Implement the model.** Normalization helper `_normalizeMobile(String)` strips spaces/dashes, leading `+966`, then leading `0`; valid when result is 9 digits. Keep validators as separate methods so the UI can show per-field messages.

- [x] **Step 4: Write failing widget test** in `test/features/claim_form_screen_test.dart`.
  - Add mode: pump screen; tap save with empty fields → all required field errors visible (`S.requiredField` count ≥ 5) AND no `onSaved` call (record via callback).
  - **Input preservation on validation failure:** type name "خالد", mobile "abc"; tap save → error shown for mobile, and the name field STILL contains "خالد" (assert `tester.enterText` value via `find.byType(TextField)` first entry text == 'خالد'). This pins Review Focus #1.
  - Fill everything valid; tap save → `onSaved` called exactly once with a Claim whose fields match inputs.
  - Edit mode: pass an existing claim; assert fields pre-populated (name field shows the seeded name); change one field, save → returned claim has new value AND original id/createdAt preserved.

- [x] **Step 5: Run to verify failure** — expected FAIL (screen missing).

- [x] **Step 6: Implement `ClaimFormScreen`.**
  Sections with headers per spec §7.1–§7.4: بيانات العميل / بيانات الحادث / بيانات المطالبة / المتابعة. Each field: label + `TextField` (or date picker for the two dates via a tappable row showing formatted value — use `showDatePicker(locale ar)`). Status selector: dropdown of all 10 statuses from `ClaimStatus.all` (default `new`) — this is groundwork allowed by the prompt ("minimal model groundwork"); no history writes here. Next follow-up: optional date-time picker row + "clear" action; reminder toggle disabled with hint that reminders arrive in Phase 3 (do NOT fake scheduling).
  Save button: primary teal, full width; on tap run `model` validators → if invalid, show inline errors and keep focus/input intact; if valid call `onSaved(model.applyTo(existing) or buildNew)` then pop. Cancel pops without saving.

- [x] **Step 7: Run both test files to verify they pass.**

- [x] **Step 8: Record in WORK_LOG.md.**

---

### Task 5: Claim details screen (read + edit/delete actions)

**Files:**
- Create: `lib/features/claims/claim_details_screen.dart`
- Test: extend `test/features/claim_form_screen_test.dart` or new `test/features/claim_details_screen_test.dart`

**Interfaces:**
- Consumes: `ClaimsRepository.claimById(id)` (via injected `AppDatabase`), `StatusChip`, `TimeUtils.formatDate/formatDateTime/formatSar/followUpLabel`, `S.*`.
- Produces: `class ClaimDetailsScreen extends StatefulWidget { const ClaimDetailsScreen({super.key, required this.db, required this.claimId}); }` — loads the claim on init; actions: **Edit** (pushes `ClaimFormScreen(claim)` and refreshes after save), **Delete** (confirmation dialog with `S.deleteClaimTitle/Body`, then `repo.delete(id)` + pop). Status-change and reminder flows are Phase 3 — do NOT add stub buttons for them (spec §3.3: no non-functional buttons); the screen shows current status, last update, next follow-up as read-only info rows.

- [x] **Step 1: Write failing widget test.** Seed FFI DB with one claim (all fields incl. amount 12500.5, notes). Pump details screen for that id.
  Assertions: all section labels visible (`S.customerNameLabel`, `S.accidentDateLabel`, `S.submissionDateLabel`, `S.statusLabel`, `S.lastStatusUpdateLabel`); customer name value visible; amount rendered with SAR label via `TimeUtils.formatSar`; status chip shows the seeded Arabic status.
  Tap delete → dialog appears (`S.deleteClaimTitle`) → tap confirm → claim gone: re-query repo returns null and screen popped (assert `find.byType(ClaimDetailsScreen)` misses).
  Tap cancel on dialog → claim still exists in DB.

- [x] **Step 2: Run to verify failure** — expected FAIL.

- [x] **Step 3: Implement.** Layout: `ListView` of section cards (customer / accident / claim / follow-up) each a Card with label-value rows; value alignment RTL-aware (`Row(mainAxisAlignment: spaceBetween)`); amount via `TimeUtils.formatSar`; dates via `formatDate`/`formatDateTime`. Bottom action bar: Edit (primary), Delete (tonal, red-ish semantic). Loading state while `claimById` resolves; not-found state with back button if the claim was deleted elsewhere.

- [x] **Step 4: Run to verify pass.**

- [x] **Step 5: Record in WORK_LOG.md.**

---

### Task 6: Settings screen (theme selection persisted + info)

**Files:**
- Create: `lib/features/settings/settings_screen.dart`
- Modify: `lib/main.dart` — expose a way for the settings screen to change the live theme mode (pass a callback or use an inherited notifier; simplest: `ClaimTrackerApp` takes an optional `onThemeModeChanged(ThemeMode)` and rebuilds)
- Test: `test/features/settings_screen_test.dart`

**Interfaces:**
- Consumes: `SettingsRepository.get/set(AppConstants.settingThemeMode, 'light'|'dark'|'system')`; `S.settings*`, `S.themeLight/Dark/System`.
- Produces: `class SettingsScreen extends StatefulWidget { const SettingsScreen({super.key, required this.settingsRepo, required this.currentThemeMode, required this.onThemeChanged}); }` — theme radio list (فاتح/داكن/اتبع النظام) persisted via the repository; notifications section shows current permission state text (read-only info using `NotificationService.instance.areNotificationsEnabled()`); about section shows app name + version placeholder string from `S.appVersion` with a constant build label.

- [x] **Step 1: Write failing widget test.** Fake/in-memory settings repo over FFI DB; pump screen with `currentThemeMode = ThemeMode.system`.
  Assertions: three theme options visible with correct Arabic labels; selecting "داكن" → `onThemeChanged` called with `ThemeMode.dark` AND `settingsRepo.get(settingThemeMode)` == 'dark' (persistence); re-pumping the screen reads back 'dark' and marks it selected.

- [x] **Step 2: Run to verify failure** — expected FAIL.

- [x] **Step 3: Implement.** Simple `ListView` of cards; theme section uses a radio-style list (three tappable rows, selected row highlighted with teal check icon); on tap → persist + call `onThemeChanged`. Notifications card: status line + hint about exact-alarm limitations (static Arabic text from `S`). About card: app name + version.

- [x] **Step 4: Run to verify pass.**

- [x] **Step 5: Record in WORK_LOG.md.**

---

### Task 7: Wire the shell — real destinations, Add Claim action, persistence end-to-end

**Files:**
- Modify: `lib/app/home_shell.dart` — replace placeholder destinations with `DashboardScreen`, `ClaimsListScreen`, Reminders (Phase 3 — keep a simple informational screen that states reminders arrive in Phase 3? NO: spec §3.3 forbids non-functional screens; instead the Reminders tab shows the claims list filtered to follow-ups, which is functional and honest), `SettingsScreen`.
- Modify: `lib/main.dart` — open `AppDatabase`, construct repositories once, pass into shell; wire theme callback from settings screen (Task 6).
- Test: extend `test/widget_test.dart` — full-shell smoke test in both themes.

**Interfaces:**
- Consumes: everything above + `ClaimsRepository.create/update/delete`.
- Produces: working app flow: Dashboard → tap metric → filtered list; List → tap card → details; Add Claim FAB (prominent, spec §4) → form → save persists to SQLite; Edit from details persists; Delete with confirmation removes.

- [x] **Step 1: Write failing end-to-end widget test** in `test/widget_test.dart` (or new file): pump the full app shell over an FFI-backed DB (in-memory path via a temp file so it survives "restart" — use `Directory.systemTemp.createTemp()` + real file path, close and reopen to simulate restart).
  Assertions:
  - FAB visible with `S.addClaim` label; tap → form appears.
  - Fill valid data, save → back on list, new card visible (persistence in same session).
  - **Restart simulation:** dispose the app widget tree, close DB, reopen a fresh `AppDatabase` over the same file path, pump shell again → the claim is still there (pins Review Focus #5).
  - Both themes: wrap pumps with `themeMode light` and `dark`; assert no exceptions and key labels visible in each.

- [x] **Step 2: Run to verify failure** — expected FAIL (shell still placeholders / wiring missing).

- [x] **Step 3: Implement the wiring.** Shell holds a single `AppDatabase` instance created in `main()`; repositories constructed once and passed down. Add Claim FAB on Dashboard + Claims list destinations. Reminders destination = `ClaimsListScreen(initialFilter: followUp)` (functional, honest). Settings per Task 6 with live theme switching.

- [x] **Step 4: Run the full suite** — `flutter analyze && dart format lib test --output=write && flutter test` → all green.

- [x] **Step 5: Build debug APK** — `flutter build apk --debug` → success; record path + size in WORK_LOG.md.

- [x] **Step 6: Update handoff docs.**
  - `IMPLEMENTATION_PROGRESS.md`: mark Phase 2 complete with the feature list, decisions (no new deps; callback-based navigation for testability; Reminders tab = follow-up-filtered list as honest interim), database behavior notes, known issues.
  - `WORK_LOG.md`: append entry — commands run + actual outcomes, screens/themes checked, exact next step for Prompt 3 (status change flow with atomic history + reminder scheduling on the existing `NotificationService`).

---

## Self-Review Notes (completed at plan time)

1. **Spec coverage:** §5 dashboard → Tasks 1–2; §6 list/search/filters/card → Task 3; §7 forms/validation → Task 4; §8 statuses centralized (already Phase 1, used by chip/dropdown); §11 details + edit/delete actions → Task 5 (status-change & reminder actions deferred to Phase 3 per prompt boundary — documented as known issue); §16 settings theme/notifications/version → Task 6. All covered or explicitly deferred with reason.
2. **Step scan:** every step has one checkable action; no "handle edge cases" lines.
3. **Type consistency:** `ClaimsFilter` defined once (Task 3) and used by Tasks 2, 7; `ClaimFormModel` signatures consistent between Task 4 steps; `DashboardService.metrics()`/`needsAttention(limit:)` consistent in Tasks 1–2.
4. **Review Focus:** all five lines pinned to named tests above.
5. **Proportion:** plan is ~same length as the spec sections it implements; bodies omitted where signatures + tests determine behavior.
