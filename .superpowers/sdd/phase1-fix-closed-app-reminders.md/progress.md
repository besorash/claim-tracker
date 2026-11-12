# SDD ledger — plan: user inline spec (Phase 1: fix reminders not arriving while app closed; Phase 2: English + language switch)

No git repo in this workspace (established convention from prior phases): progress tracked here, no commits.

## Pre-flight scan

- Shared interfaces: `ReminderScheduler` seam is consumed by ClaimActions, settings screen, claim details screen, and the new reconcile logic — all fakes must keep implementing it when the interface changes.
- `NotificationService.reconcile` is called from main.dart startup + post-restore path; changing its behavior affects both call sites (they pass `allEnabled()`).
- Security audit test pins: generic notification text, no INTERNET in production manifest, no sensitive logging, no hardcoded keys — Phase 1 changes must keep all four green.

## Rulings

- Task P1-2: reconcile decision logic extracted as a pure function (`reconcilePlan`) so it is unit-testable without method channels (host tests cannot touch flutter_local_notifications). The plugin-facing `reconcile()` becomes a thin adapter over the plan. — Cost if wrong: one extra indirection layer; acceptable for testability of the core bug fix.
- Task P1-2: CORRECTED ruling (initial draft said "reschedule late" — that would duplicate already-fired reminders because the DB has no reliable fired flag): past-due enabled reminders are NEVER re-scheduled by reconcile, whether or not a pending alarm exists. A still-pending delayed alarm is left to fire; an already-fired one is not posted twice (spec §10 "avoid duplicates" wins over late delivery). `scheduleReminder` keeps its early-return for past times.
- Task P1-2: duplicate enabled rows sharing one notificationId → the earliest fire time wins (single OS slot per id; no duplicates).
