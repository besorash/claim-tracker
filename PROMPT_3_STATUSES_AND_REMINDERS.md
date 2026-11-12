# PROMPT 3 --- STATUS WORKFLOW, HISTORY, AND LOCAL REMINDERS

Continue the Claim Tracker project.

## Mandatory preparation

Read `MASTER_PROJECT_SPEC.md`, `IMPLEMENTATION_PROGRESS.md`, and
`WORK_LOG.md`. Inspect the current code and verify Phase 2. Fix
regressions before adding features.

## Scope for this phase

Implement Phase 3: - The ten approved default claim statuses. - Status
update UI. - Persistent status history. - Per-claim custom reminders. -
Local Android notifications. - Reminder list / follow-up view. -
Notification routing to the correct claim. - Reminder cancellation and
rescheduling rules.

## Status history

Follow Section 9 of the master spec. The claim status update and status
history insert must be atomic in a SQLite transaction. Show history in
claim details. Never overwrite or discard prior history when a status
changes.

## Reminders

Follow Section 10 of the master spec. Implement one-time reminders
robustly first. Add recurring intervals in hours/days only if the
selected Android APIs and package support them reliably.

Persist reminder definitions in SQLite. Handle: - Permission requests
and denied permission state - Notification channels - Stable
notification IDs - Rescheduling after edits - Cancellation after
disable, claim closure, or deletion - Reconciliation after app restart
and device reboot - Timezone and date-boundary behavior - Android
exact-alarm restrictions - Duplicate notification prevention -
Notification tap navigation to the correct claim

Do not expose sensitive customer information in lock-screen notification
text by default.

## User experience

-   In the status-change flow, offer an optional next follow-up
    date/time.
-   Make overdue and due-today claims easy to identify.
-   Provide clear Arabic explanations when notifications are disabled or
    restricted.
-   Keep the Premium Modern design and both themes consistent.

## Verification required

Test scheduling, persistence, rescheduling, disabling, closing,
deleting, reboot/restart reconciliation, permission-denied behavior,
notification routing, and timezone boundaries as far as the environment
permits.

Run formatter, static analysis, tests, and Android debug build. Fix
issues before handoff.

## Handoff

Update progress and work log with exact commands, actual results,
platform/API limitations, and remaining issues. Do not claim reboot or
notification delivery testing unless it was actually performed.
